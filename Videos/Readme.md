# Video Processing and Synchronisation Pipeline

## Overview
This repository contains the code and documentation for the preprocessing of dyadic video recordings collected for the **HyperYESNO** project.  
The main goal of this step is to synchronise pairs of videos recorded simultaneously from two participants interacting in a face-to-face guessing task, using their shared audio tracks as a reference.

---

## Data Recording

### Recording Setup
- Each dyad consisted of **two participants** recorded **simultaneously** using **two identical laptops** (Windows 11).
- Each laptop used its **built-in camera** and **microphone** through the native **Camera app** in Windows.
- The experimenter manually started each recording; therefore, the start times of the two recordings were not perfectly aligned.
- The cameras were positioned so that the participants’ faces were **centred and clearly visible**, with **diffuse lighting** provided by a desk lamp placed behind the laptops.

### Video Characteristics
| Property | Value |
|-----------|--------|
| Frame width | 1920 px |
| Frame height | 1080 px |
| Frame rate | 30 frames / s |
| Data rate | ~12,134 kbps |
| Audio bit rate | 192 kbps |
| Audio channels | Stereo (2 channels) |
| Audio sample rate | 44,100 Hz |

Each video therefore provides high-definition footage and high-quality stereo audio suitable for subsequent synchronisation and behavioural analysis.

---

## Experimental Context
During the recording, participants in each dyad performed an **experimental task** resembling the commercial *Heads Up!* board game.  
In this task, one participant acted as the “knower” and the other as the “guesser.”  
Further details of the task and behavioural protocol are described elsewhere in the accompanying documentation and manuscript.

---

## Preprocessing Pipeline

### 1. Manual Trimming
Raw recordings were **manually trimmed** using *CapCut* video editor to remove:
- experimenter instructions,
- practice trials, and
- any other non-task segments.

The trimmed videos thus start and end approximately at the onset and offset of the experimental task.

### 2. Audio-Based Synchronisation
The trimmed videos were then synchronised using a **MATLAB-based audio alignment procedure**.  
This step corrects for the small temporal offset between the two laptops’ recordings.

#### Method
1. **Audio extraction:** Both audio tracks are extracted directly from the `.mp4` files.  
2. **Lag estimation:** The relative delay between the two signals is estimated using the **Generalised Cross-Correlation with Phase Transform (GCC-PHAT)** method, which is robust to amplitude and noise differences.  
3. **Alignment:** Depending on the estimated lag, one video is either **trimmed** or **padded** with black frames so that both start at the same moment in the output.  
4. **Export:** The synchronised videos are saved with matching start times, and a small `.mat` file is generated containing synchronisation metadata.

#### Implementation

##### 🛠️ Install FFmpeg — via `winget` (built-in package manager on Windows 11)

1. **Open PowerShell (Admin)**  
2. **Run:**
   ```powershell
   winget install --id=Gyan.FFmpeg -e
   ```
3. **Verify installation:**
   ```powershell
   ffmpeg -version
   ```
4. **You can verify that MATLAB can see FFmpeg by running:**
   ```powershell
   [st, out] = system('ffmpeg -version'); disp(out)
   ```
If st is 0 and you see version text, MATLAB can access ffmpeg.

5. **Add FFmpeg to PATH so any app (including MATLAB) can find it:** (if needed)

   - Start → type Environment Variables → Edit the system environment variables

   - Click Environment Variables…

   - Under System variables, select Path → Edit → New

   - Add the line: C:\ffmpeg\bin  

   - Confirm with OK → OK

<ins> Two MATLAB functions are used: </ins>

- **`sync_videos_by_audio.m`**  
  Performs the full synchronisation pipeline described above.  
  The function extracts both audio tracks, estimates the offset via GCC-PHAT, trims or pads the videos accordingly, writes out perfectly aligned videos, and saves a log file containing the computed lag and related parameters.

- **`wrapper4sync_videos_by_audio.m`**  
  Iterates over all dyads (Dyad01 – Dyad35), locates the appropriate `A` and `B` videos within each folder, and calls `sync_videos_by_audio` automatically.

Both scripts are included in this repository with detailed in-line documentation.

---

## Folder Structure
Each dyad directory contains two subfolders (`A_cut` and `B_cut`), corresponding to the two participants:

D:\HyperYESNO_videosCUT\Dyadxx\Dyadxx-A_cut\Dyadxx-A_.mp4

D:\HyperYESNO_videosCUT\Dyadxx\Dyadxx-B_cut\Dyadxx-B_.mp4

---

## Output Files

After running the synchronisation wrapper:

- **`DyadXX-A_sync.mp4` / `DyadXX-B_sync.mp4`**  
  Aligned video files with identical start times.

- **`DyadXX_sync_log.mat`** 
  MATLAB structure containing metadata such as:
  - `lag_seconds`: Estimated temporal offset (positive = B lags A).
  - `fs_target`: Audio sampling rate used for lag estimation. 
  - `strategy`: Whether the alignment was achieved by trimming or padding.  
  - `duration_out`: Duration of each output video (seconds).
  - `video_fps`: frames per second
  - `notes`: Short description of conventions used.

---

## Reproducibility Notes
- The synchronisation was performed using MATLAB R2026a and the built-in `VideoReader`, `VideoWriter`, and `audioread` functions.  
- The `TargetFs` parameter was set to **41,000 Hz**, the native sample rate of the recordings, for keeping the temporal precision.  
- All parameters are configurable in the wrapper script.

---
## Head Motion Tracking

### 2. Create a Virtual Environment

Open **PowerShell (Admin)** and run:

```powershell
python -m venv C:\dev
envs\hyperyesno
```

Activate the environment:

```powershell
C:\dev
envs\hyperyesno\Scripts ctivate
```

---

### 3. Install Required Packages

Install the necessary dependencies:

```powershell
pip install mediapipe==0.10.11 opencv-python==4.12.0 numpy scipy
```

Check that all packages were installed correctly:

```powershell
pip list
```

---

### 4. Link Python to MATLAB

In **MATLAB**, run:

```matlab
pyenv('Version','C:\dev
envs\hyperyesno\Scripts\python.exe')
```

This ensures MATLAB uses the same Python environment with all dependencies.

---

## ⚙️ Motion Extraction Pipeline

### Step 1. Single-Video Analysis

Each video is processed by the Python script **`head_motion_unified.py`**, which performs the following steps:

1. Loads frames using **OpenCV**.  
2. Detects faces with **MediaPipe** and keeps only the **highest-confidence face** per frame.  
3. Estimates **head pose** (yaw, pitch, roll, and translation vector *t⃗*).  
4. Computes:
   - **Bounding-box composite:** translational motion in x/y and apparent depth.  
   - **Head-pose composite:** rotational (yaw/pitch/roll) and translational speeds.  
5. Fuses both as a **unitary head-motion measure**:

   ```math
   Mₜ = √[(β·z(v_bbox,t))² + ((1−β)·z(v_pose,t))²]
   ```

   where β = 0.5 by default.

Each analysis generates:

- A `.csv` file containing framewise data.  
- An optional `.mp4` preview showing tracked faces and pose axes.

---

### Step 2. MATLAB Integration

MATLAB wrapper functions manage batch execution:

- **`run_head_motion_unified.m`**  
  Wrapper that calls the Python script for one participant video.

- **`batch_head_motion_unified.m`**  
  Runs the pipeline across all dyads, handling paths, logging, and error capture.

- **`rerun_failed_head_motion_unified.m`**  
  Selectively re-runs failed cases (e.g., specific `DyadXX-A/B` videos).

**Example MATLAB call:**

```matlab
run_head_motion_unified('D:\HyperYESNO_videosCUT\Dyad04\Dyad04-A_cut\Dyad04-A_sync.mp4', ...
                        'Dyad04-A_motion.csv', 'Dyad04-A_motion_preview.mp4');
```

---

## 📁 Output Files

For each processed video:

- **`DyadXX-A_motion.csv` / `DyadXX-B_motion.csv`**  
  Contains timestamp, bounding-box (x, y, w, h), yaw, pitch, roll, translation (tx, ty, tz), and fused movement metrics.

- **`DyadXX-A_motion_preview.mp4` (optional)**  
  Visualisation overlaying detection box and 3D head-pose axes.

All outputs are saved in the same folder as the synchronised videos.

---

## 🧠 Interpretation

The resulting **unitary head-motion signal (Mₜ)** provides a continuous measure of head movement magnitude per frame, integrating both translational and rotational components.  
This serves as a **proxy for communicative engagement** and can be used for **within- and between-participant synchrony analyses** across dyads.

---

## 🧾 Reproducibility Notes

- **Python version:** 3.11 (virtual environment executed from MATLAB R2025a)  
- **Packages:** `mediapipe 0.10.11`, `opencv-python 4.12.0`, `numpy`, `scipy`  
- **Frame rate:** 30 fps  
- **Resolution:** 1920 × 1080 px  
- **Face selection:** Only the face with the highest detection confidence is tracked per frame  
- **Parameters:** All parameter values (`β`, smoothing window, weighting coefficients) are configurable in the MATLAB wrappers

---

## 📚 References

based on open-source frameworks:

- Lugaresi, C., et al. (2019). *MediaPipe: A Framework for Building Perception Pipelines.*  
- Bradski, G. (2000). *The OpenCV Library.* *Dr. Dobb’s Journal of Software Tools.*  
- Baltrušaitis, T., Robinson, P., & Morency, L.-P. (2016). *OpenFace: An open source facial behavior analysis toolkit.* IEEE Winter Conference on Applications of Computer Vision (WACV).

---

*Last updated: November 2025*
