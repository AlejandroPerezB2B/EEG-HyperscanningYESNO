# EEG-Hyperscanning-YESNO

## Methods

### Task and Procedure

Participants completed a dyadic yes/no guessing task/game similar to the Hedbanz board game. They were seated side by side at a shared workstation, each facing the screen of a laptop. A response pad was placed at the centre of the table, between the laptops. In each round, one participant (“Knower”) viewed a target word on the screen; the partner (“Guesser”) could not see the word and attempted to identify it by asking yes/no questions. Participants were instructed to ask relevant, information-seeking questions (e.g., “Does it meow?”; “Is it a pet?”) and to avoid elimination strategies based on unrelated or negated queries (e.g., “Is it not a bird?”). A printed sheet with suggested questions per category (template) was available as an optional aid. The Knower answered aloud and simultaneously registered each response on the response pad using role-specific keys for each participant. Button presses were sent as triggers to the EEG acquisition system. At the end of the round, the response pad was passed to the partner as roles switched. The beginning of each turn was detected using a photodiode attached to one of the screens and also served as a trigger for the EEG.  

Stimuli were 32 target words drawn from four superordinate categories (complete list in Supplementary Materials 1): Animals, Professions, Meals, and Objects. The "Guesser" received information about the category corresponding to the turn. Example items included dog, horse, lion (Animals); doctor, teacher, pilot (Professions); pizza, sushi, cake (Meals) and laptop, toothbrush, chair (Objects). In the case of the broader Object category, an additional hint was provided (e.g., "transport" for Object "car"). The presentation order of the target words was identical for all dyads. Each round lasted 60 seconds maximum. However, if a round concluded before (i.e., a correct guess), participants can advance immediately to the subsequent trial. Both partners shared control of the presentation to proceed and could advance the trial when ready (self-paced). Before the main task, participants completed two practice trials to familiarise themselves with the procedure and response pad. Sessions were also video-recorded with the laptops' front cameras. Participants were asked to keep their gaze on the screen and remain within the camera frame during the entire experiment.

## Step1_preprocessing_HyperYESNO.m

Scrip to import, trigger extraction, trim, split, and save

Minimal MATLAB script to load Curry EEG, decode triggers, trim, split by participants (A/B), and save EEGLAB sets per dyad.

### Workflow
- Load Curry files via `loadcurry` (**loadcurry 3.3.2** required).
- Decode triggers with `triggers_with_findpeaks.m`.
- Save snapshot (`.set`+`.fdt`, two-file), **resample to 250 Hz**.
- Remove trigger channel, **trim** to ≤5 s pre-first and post-last event.
- Split channels: `1–64 → SubjA`, `65–128 → SubjB`.
- Apply `standard-10-5-cap385.elp` to A; copy geometry to B (keep B impedances).
- Rename A: `I1` (ch 60), `I2` (ch 64). Remove `M1/M2`. Save to `DyadXX/SubjA` and `DyadXX/SubjB`.

### Input layout
```
D:\EEG_data_HyperYESNO\
  Acquisition 41.dap (+ companions)
  Acquisition 45.dap
  ...
```

Set at top:
```matlab
data_path   = 'D:\EEG_data_HyperYESNO';
subject_ids = [41, 45:78];
```

### Trigger decoding (`triggers_with_findpeaks.m`)
Stores numeric **code** in `EEG.event.value` and string **label** in `EEG.event.type`.

Mapping:
```
100240→BlockStart
100241→YES_AKnower
100242→NO_AKnower
100244→YES_BKnower
100248→NO_BKnower
100243→resp3
100252→resp12
else → unknow
```
Also collapses consecutive `BlockStart`, renumbers `urevent`, warns if `>32` blocks.

### Dependencies
- MATLAB + EEGLAB
- **loadcurry 3.3.2** plugin
- `standard-10-5-cap385.elp` (EEGLAB resource)

### Add your processing
Insert here (before A/B split or per half):
```matlab
% EEG   = myFcn(EEG);
% EEG_A = myFcn(EEG_A);
% EEG_B = myFcn(EEG_B);
```
