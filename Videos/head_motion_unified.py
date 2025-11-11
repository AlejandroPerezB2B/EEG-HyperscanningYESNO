"""
head_motion_unified.py  (robust preview version)
Compute (1) bounding-box composite, (2) head-pose composite, and (3) a unitary
movement measure for a single video, locally (MediaPipe + OpenCV).

CHANGES (robust preview):
- draw_axes() now guards against NaN/Inf points and only draws when all endpoints are valid.
- Preview block checks origin (bbox center) is finite before drawing axes.

USAGE (CLI):
    python head_motion_unified.py --video Dyad01-A_sync.mp4 \
        --out_csv Dyad01-A_motion.csv \
        --preview Dyad01-A_motion_preview.mp4

DEPENDENCIES:
    Python 3.9–3.11
    pip install mediapipe==0.10.11 opencv-python numpy scipy
"""

import argparse, math, os
import numpy as np
import cv2
from scipy.signal import medfilt
import mediapipe as mp

# ----------------------------- Utils ---------------------------------

def moving_mean_nan(x, w):
    """NaN-aware moving mean (centered window)."""
    if w <= 1: return x
    half = w // 2
    out = np.full_like(x, np.nan, dtype=float)
    for i in range(len(x)):
        a = max(0, i - half); b = min(len(x), i + half + 1)
        seg = x[a:b]
        if np.all(np.isnan(seg)): continue
        out[i] = np.nanmean(seg)
    return out

def zscore_nan(x):
    mu = np.nanmean(x)
    sd = np.nanstd(x)
    if not np.isfinite(sd) or sd == 0: sd = 1.0
    return (x - mu) / sd

def safe_int_pt(arr2):
    """Convert a 2-element array-like to int tuple if finite; else return None."""
    if arr2 is None: return None
    v = np.asarray(arr2).ravel()
    if v.size != 2: return None
    if not np.all(np.isfinite(v)): return None
    return (int(round(v[0])), int(round(v[1])))

def draw_axes(img, origin, R, length=80):
    """
    Draw 3D axes given rotation matrix R (camera coords) projected in image plane.
    Safely skips drawing if any endpoint is invalid (NaN/Inf or out-of-shape).
    """
    if R is None:
        return img
    h, w = img.shape[:2]

    # Validate and coerce origin
    o = safe_int_pt(origin)
    if o is None:
        return img

    # Approximate intrinsics (FOV ~ 60 deg)
    fx = fy = w / (2 * math.tan(math.radians(60)/2))
    cx, cy = w/2, h/2
    K = np.array([[fx,0,cx],[0,fy,cy],[0,0,1]], float)

    axis = np.float32([[length,0,0],[0,length,0],[0,0,length]]).reshape(-1,3)
    try:
        rvec, _ = cv2.Rodrigues(R)
        tvec = np.zeros((3,1))
        pts2d, _ = cv2.projectPoints(axis, rvec, tvec, K, None)
    except cv2.error:
        return img

    X = safe_int_pt(pts2d[0].ravel())
    Y = safe_int_pt(pts2d[1].ravel())
    Z = safe_int_pt(pts2d[2].ravel())
    if X is None or Y is None or Z is None:
        return img

    # Draw; wrap in try in case any coordinate is out of range for some OpenCV builds
    try:
        cv2.line(img, o, X, (0,0,255), 2)   # x: red
        cv2.line(img, o, Y, (0,255,0), 2)   # y: green
        cv2.line(img, o, Z, (255,0,0), 2)   # z: blue
    except cv2.error:
        pass
    return img

def euler_from_R(R):
    """Yaw-Pitch-Roll (Z-Y-X) in degrees from rotation matrix R."""
    sy = math.sqrt(R[0,0]*R[0,0] + R[1,0]*R[1,0])
    singular = sy < 1e-6
    if not singular:
        yaw   = math.degrees(math.atan2(R[1,0], R[0,0]))
        pitch = math.degrees(math.atan2(-R[2,0], sy))
        roll  = math.degrees(math.atan2(R[2,1], R[2,2]))
    else:
        yaw   = math.degrees(math.atan2(-R[0,1], R[1,1]))
        pitch = math.degrees(math.atan2(-R[2,0], sy))
        roll  = 0.0
    return yaw, pitch, roll

# Canonical 3D facial keypoints (approx units)
FACE3D = {
    'nose_tip':     np.array([0.0,    0.0,    0.0], dtype=float),
    'chin':         np.array([0.0,   -63.6,  -12.5]),
    'left_eye_o':   np.array([-43.3,  32.7,  -26.0]),
    'right_eye_o':  np.array([ 43.3,  32.7,  -26.0]),
    'left_mouth':   np.array([-28.9, -28.9,  -24.1]),
    'right_mouth':  np.array([ 28.9, -28.9,  -24.1]),
}

# MediaPipe Face Mesh indices (468-landmark model)
LM_IDX = {
    'nose_tip':    1,
    'chin':        152,
    'left_eye_o':  33,
    'right_eye_o': 263,
    'left_mouth':  61,
    'right_mouth': 291,
}

def pick_2d_points(landmarks, W, H):
    """Extract required 2D points from MediaPipe landmarks -> pixel coords."""
    pts = {}
    for k, idx in LM_IDX.items():
        lm = landmarks[idx]
        x = lm.x * W
        y = lm.y * H
        pts[k] = np.array([x, y], dtype=float)
    return pts

def solve_head_pose(pts2d, W, H):
    """Estimate pose (R, t) from 2D–3D correspondences using solvePnP."""
    fx = fy = W / (2 * math.tan(math.radians(60)/2))
    cx, cy = W/2, H/2
    K = np.array([[fx,0,cx],[0,fy,cy],[0,0,1]], dtype=float)
    dist = np.zeros(5)

    obj = np.vstack([FACE3D['nose_tip'],
                     FACE3D['chin'],
                     FACE3D['left_eye_o'],
                     FACE3D['right_eye_o'],
                     FACE3D['left_mouth'],
                     FACE3D['right_mouth']]).astype(np.float32)
    img = np.vstack([pts2d['nose_tip'],
                     pts2d['chin'],
                     pts2d['left_eye_o'],
                     pts2d['right_eye_o'],
                     pts2d['left_mouth'],
                     pts2d['right_mouth']]).astype(np.float32)

    ok, rvec, tvec = cv2.solvePnP(obj, img, K, dist, flags=cv2.SOLVEPNP_ITERATIVE)
    if not ok:
        return None, None, None
    R, _ = cv2.Rodrigues(rvec)
    yaw, pitch, roll = euler_from_R(R)
    return (R, tvec.reshape(-1), (yaw, pitch, roll))

# -------------------------- Core Processing ---------------------------

def bbox_composite_series(xs, ys, ws, hs, W, H, smooth_win=5,
                          weights_xyz=(1.0,1.0,0.8), depth_mode='log'):
    """
    Create bbox-based composite motion series:
      - normalized center: cx/W, cy/H
      - depth proxy: zproxy = -log(w/w0)  (or alt: w0/w - 1)
      - speed3d = sqrt( (wx*Δcx)² + (wy*Δcy)² + (wz*Δzproxy)² )
    Returns dict with all components.
    """
    cx = xs + ws/2.0
    cy = ys + hs/2.0
    cxn = cx / W
    cyn = cy / H

    w0 = np.nanmedian(ws) if np.isfinite(np.nanmedian(ws)) else np.nanmean(ws)
    if depth_mode == 'log':
        zproxy = -np.log(ws / w0)
    else:
        zproxy = (w0 / ws) - 1.0

    cxn_s = moving_mean_nan(cxn, smooth_win)
    cyn_s = moving_mean_nan(cyn, smooth_win)
    zp_s  = moving_mean_nan(zproxy, smooth_win)

    dcx = np.diff(cxn_s, prepend=cxn_s[:1])
    dcy = np.diff(cyn_s, prepend=cyn_s[:1])
    dz  = np.diff(zp_s,  prepend=zp_s[:1])

    wx, wy, wz = weights_xyz
    speed_xy   = np.hypot(dcx, dcy)
    speed_3d   = np.sqrt((wx*dcx)**2 + (wy*dcy)**2 + (wz*dz)**2)

    return {
        'cxn': cxn_s, 'cyn': cyn_s, 'zproxy': zp_s,
        'dcx': dcx,   'dcy': dcy,   'dz': dz,
        'speed_xy': speed_xy, 'speed_3d': speed_3d
    }

def pose_composite_series(yaw, pitch, roll, tvecs, smooth_win=5,
                          ang_weights=(1.0,1.0,1.0), trans_weight=1.0):
    """
    Create pose-based composite motion series:
      - angular speed from Δyaw, Δpitch, Δroll (degrees/frame)
      - translational speed from Δt (normalized by robust scale)
      - pose_speed = sqrt( ang_speed^2 + (α * trans_speed)^2 )
    """
    yaw_s   = moving_mean_nan(yaw,   smooth_win)
    pitch_s = moving_mean_nan(pitch, smooth_win)
    roll_s  = moving_mean_nan(roll,  smooth_win)

    dyaw   = np.diff(yaw_s,   prepend=yaw_s[:1])
    dpitch = np.diff(pitch_s, prepend=pitch_s[:1])
    droll  = np.diff(roll_s,  prepend=roll_s[:1])

    wy, wp, wr = ang_weights
    ang_speed = np.sqrt((wy*dyaw)**2 + (wp*dpitch)**2 + (wr*droll)**2)

    if tvecs is not None and np.isfinite(tvecs).any():
        norms = np.linalg.norm(tvecs, axis=1)
        scale = np.nanmedian(norms)
        if not np.isfinite(scale) or scale <= 0: scale = 1.0
        tnorm = tvecs / scale
        dt    = np.vstack([tnorm[0], np.diff(tnorm, axis=0)])
        trans_speed = np.linalg.norm(dt, axis=1)
    else:
        trans_speed = np.zeros_like(ang_speed)

    pose_speed = np.sqrt( ang_speed**2 + (trans_weight * trans_speed)**2 )

    return {
        'yaw': yaw_s, 'pitch': pitch_s, 'roll': roll_s,
        'dyaw': dyaw, 'dpitch': dpitch, 'droll': droll,
        'trans_speed': trans_speed, 'ang_speed': ang_speed,
        'pose_speed': pose_speed
    }

def run(video_path, out_csv, out_preview=None,
        smooth_win=5, weights_xyz=(1,1,0.8), ang_weights=(1,1,1),
        trans_weight=1.0, beta=0.5, depth_mode='log', draw_step=1):
    """
    Process one video and write CSV + optional preview MP4.

    beta = weight for bbox vs pose in the unitary measure, 0..1
           unitary = sqrt( (beta*z(bbox_speed))^2 + ((1-beta)*z(pose_speed))^2 )
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")
    fps = cap.get(cv2.CAP_PROP_FPS)
    W   = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    H   = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    n_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    # MediaPipe Face Mesh + Face Detection
    mp_face = mp.solutions.face_mesh
    mp_det  = mp.solutions.face_detection
    face_mesh = mp_face.FaceMesh(
        max_num_faces=1,
        refine_landmarks=True,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5
    )
    face_det = mp_det.FaceDetection(model_selection=1, min_detection_confidence=0.5)

    writer = None
    if out_preview:
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        writer = cv2.VideoWriter(out_preview, fourcc, fps, (W, H))

    # Storage
    frame_idx = []
    time_sec  = []
    has_face  = []

    xs=[]; ys=[]; ws=[]; hs=[]
    yaws=[]; pitchs=[]; rolls=[]; tvecs=[]
    Rmats=[]

    idx = 0
    while True:
        ok, frame = cap.read()
        if not ok: break
        idx += 1
        t = (idx-1)/fps

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        # --- BBOX via MediaPipe FaceDetection (best-scoring face only) ---
        det = face_det.process(rgb)
        if det.detections:
            det_best = max(det.detections, key=lambda d: d.score[0])
            bb  = det_best.location_data.relative_bounding_box
            x = max(0.0, bb.xmin) * W
            y = max(0.0, bb.ymin) * H
            w = bb.width  * W
            h = bb.height * H
            xs.append(x); ys.append(y); ws.append(w); hs.append(h)
            has_f = 1
        else:
            xs.append(np.nan); ys.append(np.nan); ws.append(np.nan); hs.append(np.nan)
            has_f = 0

        # --- LANDMARKS + POSE via FaceMesh + solvePnP ---
        lm_res = face_mesh.process(rgb)
        yaw=pitch=roll=np.nan; tvec = np.array([np.nan, np.nan, np.nan]); R=None
        if lm_res.multi_face_landmarks:
            lms = lm_res.multi_face_landmarks[0].landmark
            pts2d = pick_2d_points(lms, W, H)
            R, tvec, angles = solve_head_pose(pts2d, W, H)
            if R is not None:
                yaw, pitch, roll = angles

        yaws.append(yaw); pitchs.append(pitch); rolls.append(roll); tvecs.append(tvec); Rmats.append(R)
        frame_idx.append(idx); time_sec.append(t); has_face.append(has_f)

        # --- Preview rendering (robust) ---
        if writer and ((idx-1) % draw_step == 0):
            disp = frame.copy()

            if has_f and np.isfinite([x,y,w,h]).all():
                cv2.rectangle(disp, (int(x),int(y)), (int(x+w),int(y+h)), (0,255,0), 2)

            if R is not None and has_f and np.isfinite([x,y,w,h]).all():
                origin = (int(x+w/2), int(y+h/2))
                disp = draw_axes(disp, origin, R, length=80)

            txt = f"f={idx} face={has_f} yaw={yaw:.1f} pitch={pitch:.1f} roll={roll:.1f}"
            cv2.putText(disp, txt, (10,25), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255,255,255), 2)
            writer.write(disp)

    cap.release()
    if writer: writer.release()

    # Convert to arrays
    frame_idx = np.array(frame_idx); time_sec = np.array(time_sec); has_face = np.array(has_face)
    xs = np.array(xs); ys = np.array(ys); ws = np.array(ws); hs = np.array(hs)
    yaws   = np.array(yaws); pitchs = np.array(pitchs); rolls = np.array(rolls)
    tvecs  = np.vstack(tvecs)

    # --- BBOX composite ---
    bbox = bbox_composite_series(xs, ys, ws, hs, W, H, smooth_win=smooth_win,
                                 weights_xyz=weights_xyz, depth_mode=depth_mode)

    # --- Pose composite ---
    pose = pose_composite_series(yaws, pitchs, rolls, tvecs, smooth_win=smooth_win,
                                 ang_weights=ang_weights, trans_weight=trans_weight)

    # --- Unitary measure (fused) ---
    bbox_z = zscore_nan(bbox['speed_3d'])
    pose_z = zscore_nan(pose['pose_speed'])
    unitary = np.sqrt( (beta * bbox_z)**2 + ((1.0 - beta) * pose_z)**2 )

    # --- Save CSV ---
    import csv
    header = [
        'frame_idx','time_sec','has_face',
        'x','y','w','h',
        'cxn','cyn','zproxy','dcx','dcy','dz','bbox_speed_xy','bbox_speed_3d',
        'yaw','pitch','roll','dyaw','dpitch','droll','ang_speed','trans_speed','pose_speed',
        'unitary'
    ]
    with open(out_csv, 'w', newline='') as f:
        wcsv = csv.writer(f)
        wcsv.writerow(header)
        for i in range(len(frame_idx)):
            wcsv.writerow([
                int(frame_idx[i]), float(time_sec[i]), int(has_face[i]),
                float(xs[i]), float(ys[i]), float(ws[i]), float(hs[i]),
                float(bbox['cxn'][i]), float(bbox['cyn'][i]), float(bbox['zproxy'][i]),
                float(bbox['dcx'][i]), float(bbox['dcy'][i]), float(bbox['dz'][i]),
                float(bbox['speed_xy'][i]), float(bbox['speed_3d'][i]),
                float(yaws[i]), float(pitchs[i]), float(rolls[i]),
                float(pose['dyaw'][i]), float(pose['dpitch'][i]), float(pose['droll'][i]),
                float(pose['ang_speed'][i]), float(pose['trans_speed'][i]), float(pose['pose_speed'][i]),
                float(unitary[i])
            ])

    print(f"[done] {video_path}")
    print(f"  fps≈{fps:.3f}  size={W}x{H}  frames={n_frames}")
    print(f"  CSV -> {out_csv}")
    if out_preview:
        print(f"  Preview -> {out_preview}")

# ------------------------------ CLI ----------------------------------

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--video",    required=True, help="Path to input video (.mp4)")
    ap.add_argument("--out_csv",  required=True, help="Output CSV path")
    ap.add_argument("--preview",  default="",    help="Optional preview MP4 path")
    ap.add_argument("--smooth",   type=int, default=5,   help="Smoothing window (frames)")
    ap.add_argument("--wx",       type=float, default=1.0)
    ap.add_argument("--wy",       type=float, default=1.0)
    ap.add_argument("--wz",       type=float, default=0.8)
    ap.add_argument("--awyaw",    type=float, default=1.0)
    ap.add_argument("--awpitch",  type=float, default=1.0)
    ap.add_argument("--awroll",   type=float, default=1.0)
    ap.add_argument("--alpha",    type=float, default=1.0, help="Translation weight in pose")
    ap.add_argument("--beta",     type=float, default=0.5, help="BBox vs Pose fusion weight (0..1)")
    ap.add_argument("--depthmode",choices=["log","inv"], default="log")
    ap.add_argument("--drawstep", type=int, default=1,    help="Draw every Nth frame in preview")
    args = ap.parse_args()

    run(
        video_path=args.video,
        out_csv=args.out_csv,
        out_preview=(args.preview if args.preview else None),
        smooth_win=args.smooth,
        weights_xyz=(args.wx,args.wy,args.wz),
        ang_weights=(args.awyaw,args.awpitch,args.awroll),
        trans_weight=args.alpha,
        beta=args.beta,
        depth_mode=args.depthmode,
        draw_step=args.drawstep
    )
