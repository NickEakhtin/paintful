shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;
stencil_mode write, compare_always, 1;

// Protect the whole projected silhouette, including recessed surfaces.
void fragment() { ALPHA = 0.0; }
