// High->low decimate + reunwrap + texture bake.
// usage: bake <workdir> <target_tris> <tex_res>
#include "meshoptimizer.h"
#include "xatlas.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cmath>
#include <vector>
#include <string>
#include <algorithm>
#include <atomic>
#include <thread>
#include <fstream>

struct V3 { float x, y, z; };
static inline V3 operator+(V3 a, V3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
static inline V3 operator-(V3 a, V3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
static inline V3 operator*(V3 a, float s) { return {a.x * s, a.y * s, a.z * s}; }
static inline float dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static inline V3 cross(V3 a, V3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
static inline float len(V3 a) { return std::sqrt(dot(a, a)); }
static inline V3 norm(V3 a) { float l = len(a); return l > 1e-20f ? a * (1.f / l) : V3{0, 0, 1}; }

template <class T> std::vector<T> readf(const std::string& p) {
	std::ifstream f(p, std::ios::binary | std::ios::ate);
	if (!f) { fprintf(stderr, "cannot read %s\n", p.c_str()); exit(1); }
	size_t n = f.tellg(); f.seekg(0);
	std::vector<T> v(n / sizeof(T)); f.read((char*)v.data(), n); return v;
}
template <class T> void writef(const std::string& p, const std::vector<T>& v) {
	std::ofstream f(p, std::ios::binary); f.write((const char*)v.data(), v.size() * sizeof(T));
}

// ---------------- BVH ----------------
struct Node { float mn[3], mx[3]; int left, count, start; };
struct BVH {
	std::vector<Node> nodes; std::vector<int> tri;
	const std::vector<V3>* P; const std::vector<uint32_t>* I;
	std::vector<V3> cen, bmn, bmx;
	void build(const std::vector<V3>& p, const std::vector<uint32_t>& idx) {
		P = &p; I = &idx; size_t nt = idx.size() / 3;
		tri.resize(nt); cen.resize(nt); bmn.resize(nt); bmx.resize(nt);
		for (size_t t = 0; t < nt; t++) {
			tri[t] = (int)t; V3 a = p[idx[3 * t]], b = p[idx[3 * t + 1]], c = p[idx[3 * t + 2]];
			bmn[t] = {std::min({a.x, b.x, c.x}), std::min({a.y, b.y, c.y}), std::min({a.z, b.z, c.z})};
			bmx[t] = {std::max({a.x, b.x, c.x}), std::max({a.y, b.y, c.y}), std::max({a.z, b.z, c.z})};
			cen[t] = (a + b + c) * (1.f / 3);
		}
		nodes.reserve(nt * 2 / 2 + 16);
		nodes.push_back({});
		rec(0, 0, (int)nt);
	}
	void bounds(Node& n, int s, int c) {
		for (int k = 0; k < 3; k++) { n.mn[k] = 1e30f; n.mx[k] = -1e30f; }
		for (int i = s; i < s + c; i++) {
			int t = tri[i]; const float* a = &bmn[t].x; const float* b = &bmx[t].x;
			for (int k = 0; k < 3; k++) { n.mn[k] = std::min(n.mn[k], a[k]); n.mx[k] = std::max(n.mx[k], b[k]); }
		}
	}
	void rec(int ni, int s, int c) {
		bounds(nodes[ni], s, c);
		if (c <= 4) { nodes[ni].left = -1; nodes[ni].start = s; nodes[ni].count = c; return; }
		float cmn[3] = {1e30f, 1e30f, 1e30f}, cmx[3] = {-1e30f, -1e30f, -1e30f};
		for (int i = s; i < s + c; i++) { const float* q = &cen[tri[i]].x; for (int k = 0; k < 3; k++) { cmn[k] = std::min(cmn[k], q[k]); cmx[k] = std::max(cmx[k], q[k]); } }
		int ax = 0; for (int k = 1; k < 3; k++) if (cmx[k] - cmn[k] > cmx[ax] - cmn[ax]) ax = k;
		int mid = s + c / 2;
		std::nth_element(tri.begin() + s, tri.begin() + mid, tri.begin() + s + c, [&](int a, int b) { return (&cen[a].x)[ax] < (&cen[b].x)[ax]; });
		int l = (int)nodes.size(); nodes.push_back({}); nodes.push_back({});
		nodes[ni].left = l; nodes[ni].count = 0;
		rec(l, s, mid - s); rec(l + 1, mid, s + c - mid);
	}
	static bool slab(const Node& n, V3 o, V3 inv, float t0, float t1, float& en, float& ex) {
		const float* oo = &o.x; const float* iv = &inv.x;
		for (int k = 0; k < 3; k++) {
			float a = (n.mn[k] - oo[k]) * iv[k], b = (n.mx[k] - oo[k]) * iv[k];
			if (a > b) std::swap(a, b);
			t0 = std::max(t0, a); t1 = std::min(t1, b);
			if (t0 > t1) return false;
		}
		en = t0; ex = t1; return true;
	}
	// find hit with t closest to tref in [0, tmax]; returns tri or -1
	int query(V3 o, V3 d, float tmax, float tref, float& bt, float& bu, float& bv) const {
		V3 inv = {1.f / (std::fabs(d.x) > 1e-12f ? d.x : 1e-12f), 1.f / (std::fabs(d.y) > 1e-12f ? d.y : 1e-12f), 1.f / (std::fabs(d.z) > 1e-12f ? d.z : 1e-12f)};
		int best = -1; float bestd = 1e30f;
		int stack[128]; int sp = 0; stack[sp++] = 0;
		while (sp) {
			const Node& n = nodes[stack[--sp]]; float en, ex;
			if (!slab(n, o, inv, 0.f, tmax, en, ex)) continue;
			// lower bound of |t - tref| for t in [en,ex]
			float lb = (tref < en) ? en - tref : (tref > ex ? tref - ex : 0.f);
			if (lb >= bestd) continue;
			if (n.left < 0) {
				for (int i = n.start; i < n.start + n.count; i++) {
					int t = tri[i]; const auto& Pp = *P; const auto& Ii = *I;
					V3 a = Pp[Ii[3 * t]], b = Pp[Ii[3 * t + 1]], c = Pp[Ii[3 * t + 2]];
					V3 e1 = b - a, e2 = c - a, pv = cross(d, e2); float det = dot(e1, pv);
					if (std::fabs(det) < 1e-14f) continue;
					float id = 1.f / det; V3 tv = o - a; float u = dot(tv, pv) * id; if (u < -1e-5f || u > 1 + 1e-5f) continue;
					V3 qv = cross(tv, e1); float v = dot(d, qv) * id; if (v < -1e-5f || u + v > 1 + 1e-5f) continue;
					float tt = dot(e2, qv) * id; if (tt < 0 || tt > tmax) continue;
					float dd = std::fabs(tt - tref);
					if (dd < bestd) { bestd = dd; best = t; bt = tt; bu = u; bv = v; }
				}
			} else { stack[sp++] = n.left; stack[sp++] = n.left + 1; }
		}
		return best;
	}
};

struct Tex { int w, h; std::vector<uint8_t> d; bool ok = false; };
static Tex loadtex(const std::string& p, int w, int h) { Tex t; t.w = w; t.h = h; std::ifstream f(p, std::ios::binary); if (!f) return t; t.d = readf<uint8_t>(p); t.ok = true; return t; }
static inline void sample(const Tex& t, float u, float v, float out[3]) {
	u -= std::floor(u); v -= std::floor(v);
	float x = u * t.w - 0.5f, y = v * t.h - 0.5f; int x0 = (int)std::floor(x), y0 = (int)std::floor(y); float fx = x - x0, fy = y - y0;
	auto px = [&](int xx, int yy, int c) { xx = (xx % t.w + t.w) % t.w; yy = (yy % t.h + t.h) % t.h; return (float)t.d[((size_t)yy * t.w + xx) * 3 + c]; };
	for (int c = 0; c < 3; c++) out[c] = (px(x0, y0, c) * (1 - fx) + px(x0 + 1, y0, c) * fx) * (1 - fy) + (px(x0, y0 + 1, c) * (1 - fx) + px(x0 + 1, y0 + 1, c) * fx) * fy;
}

int main(int argc, char** argv) {
	std::string W = argv[1]; size_t target = atoi(argv[2]); int R = atoi(argv[3]);
	int TW = atoi(argv[4]), TH = atoi(argv[5]);
	auto pf = readf<float>(W + "/pos.f32"); auto nf = readf<float>(W + "/nrm.f32"); auto uf = readf<float>(W + "/uv.f32"); auto Ih = readf<uint32_t>(W + "/idx.u32");
	size_t nv = pf.size() / 3;
	std::vector<V3> Ph(nv), Nh(nv); for (size_t i = 0; i < nv; i++) { Ph[i] = {pf[3 * i], pf[3 * i + 1], pf[3 * i + 2]}; Nh[i] = {nf[3 * i], nf[3 * i + 1], nf[3 * i + 2]}; }
	V3 bmn = Ph[0], bmx = Ph[0]; for (auto& p : Ph) { bmn = {std::min(bmn.x, p.x), std::min(bmn.y, p.y), std::min(bmn.z, p.z)}; bmx = {std::max(bmx.x, p.x), std::max(bmx.y, p.y), std::max(bmx.z, p.z)}; }
	float diag = len(bmx - bmn);
	fprintf(stderr, "high: %zu verts %zu tris, diag %.3f\n", nv, Ih.size() / 3, diag);

	// ---- weld by position and simplify
	std::vector<unsigned int> remap(nv);
	size_t nu = meshopt_generateVertexRemap(remap.data(), Ih.data(), Ih.size(), Ph.data(), nv, sizeof(V3));
	std::vector<V3> Pw(nu); meshopt_remapVertexBuffer(Pw.data(), Ph.data(), nv, sizeof(V3), remap.data());
	std::vector<uint32_t> Iw(Ih.size()); meshopt_remapIndexBuffer(Iw.data(), Ih.data(), Ih.size(), remap.data());
	std::vector<uint32_t> Il(Iw.size()); float err = 0;
	size_t nl = meshopt_simplify(Il.data(), Iw.data(), Iw.size(), &Pw[0].x, nu, sizeof(V3), target * 3, 1.f, 0, &err);
	fprintf(stderr, "simplify: %zu tris, rel err %.4f\n", nl / 3, err);
	if (nl > target * 3 * 105 / 100) {
		nl = meshopt_simplifySloppy(Il.data(), Iw.data(), Iw.size(), &Pw[0].x, nu, sizeof(V3), target * 3, 1.f, &err);
		fprintf(stderr, "sloppy: %zu tris, rel err %.4f\n", nl / 3, err);
	}
	Il.resize(nl);
	std::vector<unsigned int> rm2(nu); size_t nlv = meshopt_optimizeVertexFetchRemap(rm2.data(), Il.data(), Il.size(), nu);
	std::vector<V3> Pl(nlv); meshopt_remapVertexBuffer(Pl.data(), Pw.data(), nu, sizeof(V3), rm2.data());
	meshopt_remapIndexBuffer(Il.data(), Il.data(), Il.size(), rm2.data());
	// smooth normals
	std::vector<V3> Nl(nlv, V3{0, 0, 0});
	for (size_t t = 0; t < Il.size(); t += 3) { V3 a = Pl[Il[t]], b = Pl[Il[t + 1]], c = Pl[Il[t + 2]]; V3 n = cross(b - a, c - a); for (int k = 0; k < 3; k++) Nl[Il[t + k]] = Nl[Il[t + k]] + n; }
	for (auto& n : Nl) n = norm(n);

	// ---- xatlas
	xatlas::Atlas* atlas = xatlas::Create();
	xatlas::MeshDecl md; md.vertexCount = (uint32_t)nlv; md.vertexPositionData = Pl.data(); md.vertexPositionStride = sizeof(V3);
	md.vertexNormalData = Nl.data(); md.vertexNormalStride = sizeof(V3);
	md.indexCount = (uint32_t)Il.size(); md.indexData = Il.data(); md.indexFormat = xatlas::IndexFormat::UInt32;
	if (xatlas::AddMesh(atlas, md) != xatlas::AddMeshError::Success) { fprintf(stderr, "xatlas addmesh failed\n"); return 1; }
	xatlas::ChartOptions co; co.maxIterations = 2;
	xatlas::PackOptions po; po.resolution = R; po.padding = 6; po.bilinear = true; po.blockAlign = false; po.bruteForce = false;
	xatlas::Generate(atlas, co, po);
	fprintf(stderr, "atlas: %u x %u, %u charts, %u atlases, util %.2f\n", atlas->width, atlas->height, atlas->chartCount, atlas->atlasCount, atlas->utilization[0]);
	const xatlas::Mesh& om = atlas->meshes[0];
	size_t fv = om.vertexCount; std::vector<V3> FP(fv), FN(fv); std::vector<float> FUV(fv * 2);
	for (size_t i = 0; i < fv; i++) { auto& v = om.vertexArray[i]; FP[i] = Pl[v.xref]; FN[i] = Nl[v.xref]; FUV[2 * i] = v.uv[0] / atlas->width; FUV[2 * i + 1] = v.uv[1] / atlas->height; }
	std::vector<uint32_t> FI(om.indexArray, om.indexArray + om.indexCount);
	// tangents (glTF: B = cross(N,T)*w, B points to -dP/dv)
	std::vector<V3> tacc(fv, V3{0, 0, 0}), bacc(fv, V3{0, 0, 0});
	for (size_t t = 0; t < FI.size(); t += 3) {
		uint32_t i0 = FI[t], i1 = FI[t + 1], i2 = FI[t + 2];
		V3 e1 = FP[i1] - FP[i0], e2 = FP[i2] - FP[i0];
		float du1 = FUV[2 * i1] - FUV[2 * i0], dv1 = FUV[2 * i1 + 1] - FUV[2 * i0 + 1], du2 = FUV[2 * i2] - FUV[2 * i0], dv2 = FUV[2 * i2 + 1] - FUV[2 * i0 + 1];
		float r = du1 * dv2 - du2 * dv1; if (std::fabs(r) < 1e-20f) continue; r = 1.f / r;
		V3 T = (e1 * dv2 - e2 * dv1) * r, Bv = (e2 * du1 - e1 * du2) * r; // dP/du, dP/dv
		for (uint32_t i : {i0, i1, i2}) { tacc[i] = tacc[i] + T; bacc[i] = bacc[i] + Bv * -1.f; }
	}
	std::vector<float> FT(fv * 4);
	for (size_t i = 0; i < fv; i++) {
		V3 n = FN[i], t = tacc[i]; t = t - n * dot(n, t); if (len(t) < 1e-12f) { t = cross(n, std::fabs(n.x) < 0.9f ? V3{1, 0, 0} : V3{0, 1, 0}); } t = norm(t);
		float w = dot(cross(n, t), bacc[i]) < 0 ? -1.f : 1.f;
		FT[4 * i] = t.x; FT[4 * i + 1] = t.y; FT[4 * i + 2] = t.z; FT[4 * i + 3] = w;
	}
	{ std::vector<float> a(fv * 3), b(fv * 3); for (size_t i = 0; i < fv; i++) { a[3 * i] = FP[i].x; a[3 * i + 1] = FP[i].y; a[3 * i + 2] = FP[i].z; b[3 * i] = FN[i].x; b[3 * i + 1] = FN[i].y; b[3 * i + 2] = FN[i].z; }
	  writef(W + "/low_pos.f32", a); writef(W + "/low_nrm.f32", b); writef(W + "/low_uv.f32", FUV); writef(W + "/low_tan.f32", FT); writef(W + "/low_idx.u32", FI); }
	fprintf(stderr, "low: %zu verts %zu tris\n", fv, FI.size() / 3);

	// ---- high per-tri tangent frames
	size_t nth = Ih.size() / 3;
	std::vector<V3> HT(nth), HB(nth);
	for (size_t t = 0; t < nth; t++) {
		uint32_t i0 = Ih[3 * t], i1 = Ih[3 * t + 1], i2 = Ih[3 * t + 2];
		V3 e1 = Ph[i1] - Ph[i0], e2 = Ph[i2] - Ph[i0];
		float du1 = uf[2 * i1] - uf[2 * i0], dv1 = uf[2 * i1 + 1] - uf[2 * i0 + 1], du2 = uf[2 * i2] - uf[2 * i0], dv2 = uf[2 * i2 + 1] - uf[2 * i0 + 1];
		float r = du1 * dv2 - du2 * dv1; r = std::fabs(r) < 1e-20f ? 0 : 1.f / r;
		HT[t] = (e1 * dv2 - e2 * dv1) * r; HB[t] = (e2 * du1 - e1 * du2) * (-r);
	}
	BVH bvh; bvh.build(Ph, Ih);
	fprintf(stderr, "bvh: %zu nodes\n", bvh.nodes.size());
	Tex tD = loadtex(W + "/diffuse.rgb", TW, TH), tM = loadtex(W + "/mr.rgb", TW, TH), tN = loadtex(W + "/normal.rgb", TW, TH);
	std::vector<uint8_t> oD((size_t)R * R * 3, 0), oM((size_t)R * R * 3, 0), oN((size_t)R * R * 3, 0), mask((size_t)R * R, 0);
	float maxd = 0.04f * diag;
	std::atomic<size_t> next{0}, miss{0}, hits{0};
	unsigned NT = std::max(1u, std::thread::hardware_concurrency());
	auto work = [&]() {
		size_t t;
		while ((t = next.fetch_add(1)) < FI.size() / 3) {
			uint32_t i[3] = {FI[3 * t], FI[3 * t + 1], FI[3 * t + 2]};
			float x[3], y[3]; for (int k = 0; k < 3; k++) { x[k] = FUV[2 * i[k]] * R; y[k] = FUV[2 * i[k] + 1] * R; }
			int x0 = std::max(0, (int)std::floor(std::min({x[0], x[1], x[2]})) - 1), x1 = std::min(R - 1, (int)std::ceil(std::max({x[0], x[1], x[2]})) + 1);
			int y0 = std::max(0, (int)std::floor(std::min({y[0], y[1], y[2]})) - 1), y1 = std::min(R - 1, (int)std::ceil(std::max({y[0], y[1], y[2]})) + 1);
			float den = (y[1] - y[2]) * (x[0] - x[2]) + (x[2] - x[1]) * (y[0] - y[2]); if (std::fabs(den) < 1e-12f) continue;
			for (int py = y0; py <= y1; py++) for (int px = x0; px <= x1; px++) {
				float cx = px + 0.5f, cy = py + 0.5f;
				float w0 = ((y[1] - y[2]) * (cx - x[2]) + (x[2] - x[1]) * (cy - y[2])) / den, w1 = ((y[2] - y[0]) * (cx - x[2]) + (x[0] - x[2]) * (cy - y[2])) / den, w2 = 1 - w0 - w1;
				const float eps = -0.02f; // slight conservative coverage
				if (w0 < eps || w1 < eps || w2 < eps) continue;
				V3 p = FP[i[0]] * w0 + FP[i[1]] * w1 + FP[i[2]] * w2;
				V3 n = norm(FN[i[0]] * w0 + FN[i[1]] * w1 + FN[i[2]] * w2);
				V3 tg = {FT[4 * i[0]] * w0 + FT[4 * i[1]] * w1 + FT[4 * i[2]] * w2, FT[4 * i[0] + 1] * w0 + FT[4 * i[1] + 1] * w1 + FT[4 * i[2] + 1] * w2, FT[4 * i[0] + 2] * w0 + FT[4 * i[1] + 2] * w1 + FT[4 * i[2] + 2] * w2};
				float sgn = FT[4 * i[0] + 3];
				tg = norm(tg - n * dot(n, tg)); V3 bt = cross(n, tg) * sgn;
				float bt_, bu, bv; int h = bvh.query(p + n * maxd, n * -1.f, 2 * maxd, maxd, bt_, bu, bv);
				size_t o = (size_t)py * R + px;
				if (h < 0) { miss++; continue; }
				hits++;
				uint32_t a = Ih[3 * h], b = Ih[3 * h + 1], c = Ih[3 * h + 2]; float wa = 1 - bu - bv;
				float hu = uf[2 * a] * wa + uf[2 * b] * bu + uf[2 * c] * bv, hv = uf[2 * a + 1] * wa + uf[2 * b + 1] * bu + uf[2 * c + 1] * bv;
				float col[3];
				if (tD.ok) { sample(tD, hu, hv, col); for (int k = 0; k < 3; k++) oD[o * 3 + k] = (uint8_t)std::lround(std::min(255.f, std::max(0.f, col[k]))); }
				if (tM.ok) { sample(tM, hu, hv, col); for (int k = 0; k < 3; k++) oM[o * 3 + k] = (uint8_t)std::lround(std::min(255.f, std::max(0.f, col[k]))); }
				V3 hn = norm(Nh[a] * wa + Nh[b] * bu + Nh[c] * bv);
				V3 ws = hn;
				if (tN.ok) {
					sample(tN, hu, hv, col); V3 m = {col[0] / 127.5f - 1, col[1] / 127.5f - 1, col[2] / 127.5f - 1};
					V3 T = HT[h] - hn * dot(hn, HT[h]); V3 B = HB[h] - hn * dot(hn, HB[h]);
					if (len(T) > 1e-12f && len(B) > 1e-12f) ws = norm(norm(T) * m.x + norm(B) * m.y + hn * m.z);
				}
				V3 ts = {dot(ws, tg), dot(ws, bt), dot(ws, n)}; if (ts.z < 0.05f) ts.z = 0.05f; ts = norm(ts);
				oN[o * 3] = (uint8_t)std::lround((ts.x * 0.5f + 0.5f) * 255); oN[o * 3 + 1] = (uint8_t)std::lround((ts.y * 0.5f + 0.5f) * 255); oN[o * 3 + 2] = (uint8_t)std::lround((ts.z * 0.5f + 0.5f) * 255);
				mask[o] = 255;
			}
		}
	};
	std::vector<std::thread> th; for (unsigned k = 0; k < NT; k++) th.emplace_back(work); for (auto& x : th) x.join();
	fprintf(stderr, "bake: %zu hits, %zu misses (%u threads)\n", (size_t)hits, (size_t)miss, NT);
	writef(W + "/bake_diffuse.rgb", oD); writef(W + "/bake_mr.rgb", oM); writef(W + "/bake_normal.rgb", oN); writef(W + "/bake_mask.u8", mask);
	xatlas::Destroy(atlas);
	return 0;
}
