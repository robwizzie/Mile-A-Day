# Sews a garment from its flat print outline and drapes it on a hanger with
# Blender's cloth simulation, then exports a GLB the shop's 3D rack loads.
#
#   blender -b -P scripts/sew/sew.py -- <cut> <mask.png> <out.glb>
#
# (npm run sew runs all four cuts.) The front and back panels are cut to the
# print's exact outline, so every vertex keeps the flat-lay coordinate it came
# from as its UV: front prints land on the front panel, back prints on the
# back. Edges are sewn except where a real garment is open (hem, cuffs,
# neckline, a tank's armholes); the shoulders — and a hoodie's hood — are
# pinned where the hanger holds them; then gravity, fabric stiffness and a
# little inner pressure (a garment has body) do the rest.

import json
import math
import sys

import bmesh
import bpy
import numpy as np

CUTS = {
    "tee": {"alpha": 0.5, "armY": 0.318, "cuffs": [((0.993, 0.347), (0.85, 0.403))], "fabric": "jersey"},
    "longsleeve": {"alpha": 0.5, "armY": 0.341, "cuffs": [((0.983, 0.889), (0.881, 0.907))], "fabric": "jersey"},
    "tank": {"alpha": 0.5, "armY": 0.323, "cuffs": [], "armholes": True, "fabric": "jersey"},
    "hoodie": {"alpha": 0.9, "armY": 0.70, "cuffs": [((0.993, 0.848), (0.924, 0.893))], "hood": True, "fabric": "fleece"},
}

# Weight and stiffness: a cotton tee holds its shape; fleece is heavier,
# stiffer and fuller. (Blender units: metres, kilograms.)
FABRICS = {
    "jersey": {"mass": 0.25, "tension": 30, "shear": 25, "bending": 8, "thick": 0.045},
    "fleece": {"mass": 0.45, "tension": 60, "shear": 50, "bending": 30, "thick": 0.07},
}

HEIGHT = 0.72  # the art box, in metres
GRID = 64  # columns of the panel mesh
FRAMES = 110


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :]
    cut_name, mask_path, out_path = argv[0], argv[1], argv[2]
    cut = CUTS[cut_name]
    fab = FABRICS[cut["fabric"]]

    bpy.ops.wm.read_factory_settings(use_empty=True)

    # ── Outline ──────────────────────────────────────────────────────────
    img = bpy.data.images.load(mask_path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, img.channels)
    A = px[::-1, :, 0].copy()  # mask is greyscale alpha; flip to top-down
    aspect = w / h
    thr = cut["alpha"]

    def sample(x, y):
        x = min(max(x, 0.0), w - 1.001)
        y = min(max(y, 0.0), h - 1.001)
        x0, y0 = int(x), int(y)
        fx, fy = x - x0, y - y0
        return (
            A[y0, x0] * (1 - fx) * (1 - fy)
            + A[y0, x0 + 1] * fx * (1 - fy)
            + A[y0 + 1, x0] * (1 - fx) * fy
            + A[y0 + 1, x0 + 1] * fx * fy
        )

    def solid(xn, yn):
        return sample(xn * (w - 1), yn * (h - 1)) >= thr

    def top_at(xn):
        for y in range(h):
            if solid(xn, y / (h - 1)):
                return y / (h - 1)
        return 0.0

    def bottom_at(xn):
        for y in range(h - 1, -1, -1):
            if solid(xn, y / (h - 1)):
                return y / (h - 1)
        return 1.0

    def half_run(yn):
        l = r = 0.5
        step = 1.0 / w
        while l > 0 and solid(l - step, yn):
            l -= step
        while r < 1 and solid(r + step, yn):
            r += step
        return (r - l) / 2

    torso_half = half_run(cut["armY"] + 0.06)
    neck_top, neck_half = 1.0, 0.0
    if not cut.get("hood"):
        for k in range(61):
            dx = k / 60 * torso_half * 0.6
            t = top_at(0.5 + dx)
            if t < neck_top - 1e-4:
                neck_top, neck_half = t, dx

    # Distance to the outline (metres), for the garment's starting body: a
    # garment hangs with some volume, rounding out from its seams.
    DW = 260
    DH = round(DW / aspect)
    inside = np.zeros((DH, DW), dtype=bool)
    for yy in range(DH):
        for xx in range(DW):
            inside[yy, xx] = sample(xx / (DW - 1) * (w - 1), yy / (DH - 1) * (h - 1)) >= thr
    BIG = 1e9
    D = np.where(inside, BIG, 0.0)
    r2 = math.sqrt(2)
    for yy in range(DH):
        for xx in range(DW):
            if not D[yy, xx]:
                continue
            d = D[yy, xx]
            if xx > 0:
                d = min(d, D[yy, xx - 1] + 1)
            if yy > 0:
                d = min(d, D[yy - 1, xx] + 1)
                if xx > 0:
                    d = min(d, D[yy - 1, xx - 1] + r2)
                if xx < DW - 1:
                    d = min(d, D[yy - 1, xx + 1] + r2)
            D[yy, xx] = d
    for yy in range(DH - 1, -1, -1):
        for xx in range(DW - 1, -1, -1):
            if not D[yy, xx]:
                continue
            d = D[yy, xx]
            if xx < DW - 1:
                d = min(d, D[yy, xx + 1] + 1)
            if yy < DH - 1:
                d = min(d, D[yy + 1, xx] + 1)
                if xx < DW - 1:
                    d = min(d, D[yy + 1, xx + 1] + r2)
                if xx > 0:
                    d = min(d, D[yy + 1, xx - 1] + r2)
            D[yy, xx] = d
    D = D / (DH - 1) * HEIGHT  # metres

    def dist_m(xn, yn):
        x = min(max(xn * (DW - 1), 0), DW - 1.001)
        y = min(max(yn * (DH - 1), 0), DH - 1.001)
        x0, y0 = int(x), int(y)
        fx, fy = x - x0, y - y0
        return (
            D[y0, x0] * (1 - fx) * (1 - fy) + D[y0, x0 + 1] * fx * (1 - fy) + D[y0 + 1, x0] * (1 - fx) * fy + D[y0 + 1, x0 + 1] * fx * fy
        )

    def body(xn, yn):
        """Half-thickness of the garment's starting body at a point (metres)."""
        T = fab["thick"]
        dx = abs(xn - 0.5)
        sleeve = max(0.0, dx - torso_half)
        T *= 1.0 - 0.45 * min(1.0, sleeve / 0.06)  # sleeves are slimmer
        d = dist_m(xn, yn)
        # The hem is open: the body stays full down to it (measure from the
        # side seams only), instead of pinching shut like a bag.
        if dx <= torso_half and yn > cut["armY"]:
            d = max(d, (torso_half - dx) * aspect * HEIGHT)
        e = min(d / (T * 1.3), 1.0)
        half = T * e * (2 - e)
        if cut.get("hood"):
            hood = max(0.0, min(1.0, (0.34 - yn) / 0.12))
            hood = hood * hood * (3 - 2 * hood)
            t = min(d / 0.14, 1.0)
            half += hood * 0.06 * t * (2 - t)
        return half

    # ── Panel grid, snapped to the outline ───────────────────────────────
    C = round(GRID * max(1.0, aspect))  # same cell size for wide pieces
    R = round(C / aspect)
    N = (C + 1) * (R + 1)
    mx = np.zeros(N)
    my = np.zeros(N)
    state = np.zeros(N, dtype=np.int8)  # 0 out, 1 edge, 2 inside

    def idx(i, j):
        return j * (C + 1) + i

    for j in range(R + 1):
        for i in range(C + 1):
            k = idx(i, j)
            mx[k] = i / C * (w - 1)
            my[k] = j / R * (h - 1)
            state[k] = 2 if sample(mx[k], my[k]) >= thr else 0
    snapped_x = mx.copy()
    snapped_y = my.copy()
    for j in range(R + 1):
        for i in range(C + 1):
            k = idx(i, j)
            if state[k] == 2:
                continue
            sx = sy = n = 0
            for dj in (-1, 0, 1):
                for di in (-1, 0, 1):
                    if not di and not dj:
                        continue
                    ii, jj = i + di, j + dj
                    if ii < 0 or jj < 0 or ii > C or jj > R:
                        continue
                    kk = idx(ii, jj)
                    if state[kk] != 2:
                        continue
                    lo, hi = 0.0, 1.0
                    for _ in range(8):
                        t = (lo + hi) / 2
                        if sample(mx[k] + (mx[kk] - mx[k]) * t, my[k] + (my[kk] - my[k]) * t) >= thr:
                            hi = t
                        else:
                            lo = t
                    t = (lo + hi) / 2
                    sx += mx[k] + (mx[kk] - mx[k]) * t
                    sy += my[k] + (my[kk] - my[k]) * t
                    n += 1
            if n:
                state[k] = 1
                snapped_x[k] = sx / n
                snapped_y[k] = sy / n
    mx, my = snapped_x, snapped_y

    # Faces (front winding); keep cells whose centre is fabric.
    faces = []
    for j in range(R):
        for i in range(C):
            a, b, c, d = idx(i, j), idx(i + 1, j), idx(i, j + 1), idx(i + 1, j + 1)
            quad = [a, c, d, b]
            used = [q for q in quad if state[q]]
            if len(used) == 4 and any(state[q] == 2 for q in quad):
                cx = sum(mx[q] for q in quad) / 4
                cy = sum(my[q] for q in quad) / 4
                if sample(cx, cy) >= thr * 0.7:
                    faces.append(quad)
                    continue
            for tri in ((a, c, b), (b, c, d)):
                if all(state[q] for q in tri) and any(state[q] == 2 for q in tri):
                    cx = sum(mx[q] for q in tri) / 3
                    cy = sum(my[q] for q in tri) / 3
                    if sample(cx, cy) >= thr * 0.7:
                        faces.append(list(tri))

    used = sorted({q for f in faces for q in f})
    # ── Openings: which edge points are left unsewn ───────────────────────
    def seg_dist(p, a, b):
        ax, ay = (a[0] - 0.5) * aspect, a[1]
        bx, by = (b[0] - 0.5) * aspect, b[1]
        px_, py_ = (p[0] - 0.5) * aspect, p[1]
        vx, vy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((px_ - ax) * vx + (py_ - ay) * vy) / (vx * vx + vy * vy)))
        return math.hypot(px_ - ax - vx * t, py_ - ay - vy * t)

    def is_open(k):
        xn, yn = mx[k] / (w - 1), my[k] / (h - 1)
        dx = abs(xn - 0.5)
        if dx <= torso_half + 0.01 and yn > bottom_at(xn) - 0.025:
            return True  # hem
        for a, b in cut["cuffs"]:
            for s in (1, -1):
                aa = (0.5 + s * (a[0] - 0.5), a[1])
                bb = (0.5 + s * (b[0] - 0.5), b[1])
                if seg_dist((xn, yn), aa, bb) < 0.03:
                    return True  # cuff
        if neck_half and dx < neck_half + 0.004 and yn < neck_top + 0.09:
            return True  # neckline
        if cut.get("armholes") and dx > neck_half + 0.07 and 0.07 < yn < cut["armY"] + 0.02:
            return True  # tank armhole
        return False

    def is_pinned(k):
        xn, yn = mx[k] / (w - 1), my[k] / (h - 1)
        dx = abs(xn - 0.5)
        if cut.get("hood"):
            if yn < 0.05:
                return True  # the hood's crown, on the hook
            return 0.13 < dx < torso_half * 0.85 and yn < top_at(xn) + 0.03
        return (neck_half - 0.01) < dx < torso_half * 0.95 and yn < top_at(xn) + 0.03

    # ── Mesh: front and back panels, already sewn ─────────────────────────
    # Seam points (outline, except openings) are shared by both panels, so
    # the garment is one closed shell from the start; openings keep separate
    # front and back edges. Interior points start a little apart.
    verts = []
    front_index, back_index = {}, {}
    sewn = {k for k in used if state[k] == 1 and not is_open(k)}
    for k in used:
        xn, yn = mx[k] / (w - 1), my[k] / (h - 1)
        X = (xn - 0.5) * aspect * HEIGHT
        Z = (1 - yn) * HEIGHT
        if k in sewn:
            front_index[k] = back_index[k] = len(verts)
            verts.append((X, 0.0, Z))
        else:
            half = body(xn, yn)
            front_index[k] = len(verts)
            verts.append((X, -half, Z))
            back_index[k] = len(verts)
            verts.append((X, half, Z))

    mesh = bpy.data.meshes.new(cut_name)
    bm = bmesh.new()
    bverts = [bm.verts.new(v) for v in verts]
    bm.verts.ensure_lookup_table()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for f in faces:
        fv = [bverts[front_index[q]] for q in f]
        try:
            face = bm.faces.new(fv)
        except ValueError:
            continue
        face.material_index = 0
        for loop, q in zip(face.loops, f):
            loop[uv_layer].uv = (mx[q] / (w - 1), 1 - my[q] / (h - 1))
        rf = list(reversed(f))
        bv = [bverts[back_index[q]] for q in rf]
        try:
            face = bm.faces.new(bv)
        except ValueError:
            continue
        face.material_index = 1
        for loop, q in zip(face.loops, rf):
            loop[uv_layer].uv = (1 - mx[q] / (w - 1), 1 - my[q] / (h - 1))
    bm.normal_update()
    for face in bm.faces:
        want = -1 if face.material_index == 0 else 1
        if face.normal.y * want < 0:
            face.normal_flip()
    threads = len(sewn)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(cut_name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for name in ("front", "back"):
        mat = bpy.data.materials.new(name)
        obj.data.materials.append(mat)

    pin = obj.vertex_groups.new(name="pin")
    pinned = sorted({front_index[k] for k in used if is_pinned(k)} | {back_index[k] for k in used if is_pinned(k)})
    pin.add(pinned, 1.0, "REPLACE")

    # ── Cloth ─────────────────────────────────────────────────────────────
    mod = obj.modifiers.new("Cloth", "CLOTH")
    s = mod.settings
    s.quality = 14
    s.mass = fab["mass"]
    s.air_damping = 3.0
    s.tension_stiffness = fab["tension"]
    s.compression_stiffness = fab["tension"]
    s.shear_stiffness = fab["shear"]
    s.bending_stiffness = fab["bending"]
    s.tension_damping = 8
    s.compression_damping = 8
    s.shear_damping = 8
    s.bending_damping = 1.0
    s.vertex_group_mass = "pin"
    s.pin_stiffness = 1.0
    mod.collision_settings.use_collision = True
    # Self-collision crumples these coarse panels; the starting body keeps
    # the layers apart instead.
    mod.collision_settings.use_self_collision = False
    mod.collision_settings.self_distance_min = 0.004
    mod.collision_settings.distance_min = 0.006
    mod.point_cache.frame_start = 1
    mod.point_cache.frame_end = FRAMES

    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = FRAMES
    for f in range(1, FRAMES + 1):
        scene.frame_set(f)

    # Freeze the final drape, drop the sewing threads, export.
    deps = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(deps)
    final = bpy.data.meshes.new_from_object(ev)
    bm = bmesh.new()
    bm.from_mesh(final)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(final)
    bm.free()
    for poly in final.polygons:
        poly.use_smooth = True
    out = bpy.data.objects.new(cut_name + "_draped", final)
    scene.collection.objects.link(out)
    bpy.ops.object.select_all(action="DESELECT")
    out.select_set(True)
    bpy.context.view_layer.objects.active = out
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_normals=True,
        export_texcoords=True,
        export_materials="EXPORT",
        export_yup=True,
    )
    if len(argv) > 3:
        preview(out, argv[3])
    print(json.dumps({"cut": cut_name, "verts": len(final.vertices), "faces": len(final.polygons), "threads": threads, "pinned": len(pinned)}))


def preview(obj, path):
    """Quick front + side + three-quarter renders to check a drape."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    for m in obj.data.materials:
        m.diffuse_color = (0.85, 0.25, 0.25, 1) if m.name.startswith("front") else (0.25, 0.4, 0.85, 1)
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 500
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("w")
    scene.world = world
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.6
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = (0, -4, 1.2)
    cam.rotation_euler = (math.radians(78), 0, 0)
    # three copies, turned 0, 40 and 90 degrees, side by side
    for i, turn in enumerate((0, 40, 90)):
        c = obj.copy()
        scene.collection.objects.link(c)
        c.location.x = (i - 1) * 0.85
        c.rotation_euler.z = math.radians(turn)
    obj.hide_render = True
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


main()
