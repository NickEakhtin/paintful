# Tileable wear textures for agentic (untextured) props: dark iron with copper scratches and bronze with grime.
# Writes iron_bc.png, iron_mr.png, bronze_bc.png, bronze_mr.png (1024, seamless: periodic noise via FFT).
import numpy as np
from PIL import Image
N = 1024; rng = np.random.default_rng(11)
def noise(scale, along=None):
    """Periodic gaussian-filtered noise; `along` stretches features vertically (thin streaks of width ~scale)."""
    f = np.fft.fftfreq(N)[:, None]; g = np.fft.fftfreq(N)[None, :]
    ly = along if along else scale
    spec = np.exp(-((f * ly) ** 2 + (g * scale) ** 2)) * (rng.standard_normal((N, N)) + 1j * rng.standard_normal((N, N)))
    x = np.real(np.fft.ifft2(spec)); return (x - x.mean()) / (x.std() + 1e-9)
mott = 0.6 * noise(60) + 0.4 * noise(200)
scr = noise(6, along=160)                         # long thin streaks (scratches along one axis)
spots = noise(90)
copper = np.clip((scr - 1.9) * 1.5, 0, 1) * np.clip(spots * 0.5 + 0.7, 0, 1) + np.clip((spots - 2.0) * 1.2, 0, 1)
copper = np.clip(copper, 0, 1)[..., None]
iron = np.array([30, 29, 27.]) * (1 + 0.18 * mott[..., None])
iron = iron * (1 - copper) + np.array([150, 96, 48.]) * copper
Image.fromarray(np.clip(iron, 0, 255).astype(np.uint8)).save('iron_bc.png')
mr = np.zeros((N, N, 3)); mr[..., 1] = 150 + 25 * mott - 50 * copper[..., 0]; mr[..., 2] = 110 + 140 * copper[..., 0]
Image.fromarray(np.clip(mr, 0, 255).astype(np.uint8)).save('iron_mr.png')
grime = np.clip((0.7 * noise(40) + 0.3 * noise(150) - 0.9) * 0.5, 0, 1)[..., None]
bronze = np.array([168, 114, 58.]) * (1 + 0.1 * mott[..., None])
bronze = bronze * (1 - 0.65 * grime) + np.array([45, 38, 30.]) * 0.65 * grime
Image.fromarray(np.clip(bronze, 0, 255).astype(np.uint8)).save('bronze_bc.png')
mr = np.zeros((N, N, 3)); mr[..., 1] = 85 + 90 * grime[..., 0]; mr[..., 2] = 255 - 100 * grime[..., 0]
Image.fromarray(np.clip(mr, 0, 255).astype(np.uint8)).save('bronze_mr.png')
print('ok')

# --- painted wood (blue-black paint worn through to copper-brown wood), aged copper, oxidised copper worktop ---
grain = noise(2, along=60)                         # fine vertical wood grain
chips = 0.6 * noise(26, along=60) + 0.25 * noise(9) + 0.15 * noise(3)   # flaky paint loss, elongated along the grain
edgewear = np.clip((chips - 0.8) * 2.5, 0, 1)
streak = np.clip((noise(3, along=120) - 1.7) * 1.3, 0, 1)
bare = np.clip(edgewear + 0.7 * streak, 0, 1)[..., None]
paint = np.array([30, 35, 42.]) * (1 + 0.12 * mott[..., None] + 0.06 * grain[..., None])
wood = np.array([140, 76, 36.]) * (1 + 0.15 * grain[..., None])
pw = paint * (1 - bare) + wood * bare
Image.fromarray(np.clip(pw, 0, 255).astype(np.uint8)).save('paint_bc.png')
mr = np.zeros((N, N, 3)); mr[..., 1] = 205 - 40 * bare[..., 0] + 10 * grain; mr[..., 2] = 25 + 120 * bare[..., 0]
Image.fromarray(np.clip(mr, 0, 255).astype(np.uint8)).save('paint_mr.png')
dark = np.clip((0.7 * noise(30) + 0.3 * noise(8) + 0.2) * 0.55, 0, 1)[..., None]
cu = np.array([160, 92, 46.]) * (1 + 0.1 * mott[..., None])
cu = cu * (1 - 0.7 * dark) + np.array([48, 36, 30.]) * 0.7 * dark
Image.fromarray(np.clip(cu, 0, 255).astype(np.uint8)).save('copper_bc.png')
mr = np.zeros((N, N, 3)); mr[..., 1] = 90 + 100 * dark[..., 0]; mr[..., 2] = 255 - 110 * dark[..., 0]
Image.fromarray(np.clip(mr, 0, 255).astype(np.uint8)).save('copper_mr.png')
ox = np.clip(0.78 + 0.18 * noise(60) + 0.08 * noise(12), 0, 1)[..., None]
top = np.array([44, 34, 30.]) * ox + np.array([150, 84, 42.]) * (1 - ox) * 1.1
top = top + np.array([25, 14, 6.]) * np.clip(noise(3, along=40) - 1.2, 0, 1)[..., None]
Image.fromarray(np.clip(top, 0, 255).astype(np.uint8)).save('top_bc.png')
mr = np.zeros((N, N, 3)); mr[..., 1] = 110 + 70 * ox[..., 0]; mr[..., 2] = 200 - 80 * ox[..., 0]
Image.fromarray(np.clip(mr, 0, 255).astype(np.uint8)).save('top_mr.png')
print('extra ok')
