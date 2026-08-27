## Experiment Hyper-YESNO

In the manuscript:\
**Neural and behavioural dynamics of conversational grounding during Yes-No verbal interactions**\
*Alejandro Pérez, Noah Britt, Mohammad Chaposhloo, Aaliyah Kapadia, Damián Jan, Paulo Barraza, Lorna García-Pentón,
Manuel de Vega, Sukhvinder Obhi*

### Task and Procedure

Participants completed a dyadic yes/no guessing task/game similar to the Hedbanz board game. They sat side by side at a shared workstation, each facing a laptop screen. Response pads were placed at the centre of the table, between the laptops. In each round, one participant (“Knower”) viewed a target word on the screen; the partner (“Guesser”) could not see the word and attempted to identify it by asking yes/no questions (the [Figure 1](#figure-1) is a picture of the setup). Participants were instructed to ask relevant, information-seeking questions (e.g., “Does it meow?”; “Is it a pet?”) and to avoid elimination strategies based on unrelated or negated queries (e.g., “Is it not a bird?”). A printed sheet with suggested questions per category  or [template](Question_template_for_participants.pdf) was available as an optional aid. The Knower answered aloud and simultaneously registered each response on the response pad using role-specific keys for each participant. Button presses were sent as triggers to the EEG acquisition system. At the end of the round, the roles switched. The beginning of each turn was detected using a photodiode attached to one of the screens and also served as an EEG trigger.

<p align="left"><strong>Figure 1.</strong> HyperYESNO experimental setup.</p>
<a id="figure-1"></a>
<p align="left">
  <img src="Picture_of _experimental_EEG_hyperscanning_setup.jpg" alt="Acquisition configuration in Curry.png" width="700">
</p>

Stimuli were 32 target words drawn from four superordinate categories: Animals, Professions, Meals, and Objects. The "Guesser" received information about the category for that turn. Example items included dog, horse, lion (Animals); doctor, teacher, pilot (Professions); pizza, sushi, cake (Meals); and laptop, toothbrush, chair (Objects). For the broader Object category, an additional hint was provided (e.g., "transport" for Object "car"). The presentation order of the target words was identical for all dyads. Each round lasted 60 seconds maximum. However, if a round concluded before (i.e., a correct guess), participants could advance immediately to the subsequent trial. Both partners shared control of the presentation to proceed and could advance the trial when ready (self-paced). The file [PowerPointHyperYESNO_Clean.pptx](PowerPointHyperYESNO_Clean.pptx) is the presentation used.

Before the main task, participants completed two practice trials to familiarise themselves with the procedure and response pad. Sessions were also video-recorded with the laptops' front cameras. Participants were asked to keep their gaze on the screen and remain within the camera frame during the entire experiment. We also asked participants to fill out an "Interaction Rating Scale" (included here) at the end of the experiment.

We implemented an EEG hyperscanning setup using two 64-channel Neuvo amplifiers from NeuroScan. The file "SynAmpsRT - 2 subjects - Quik-Cap 64.xml" contains the workspace used for the recording. They can copy it to:
C:\Users\<user_name>\AppData\Roaming\Neuroscan\Curry 7\Acquisition\DeviceConfigurations  (The AppData folder may be hidden!)

Curry 7 cannot separate channels of two headboxes into different groups (unlike Curry 9), so they'd have to separate the data in post-processing.
The impedance check will work for both headboxes simultaneously. However, the impedance windows will not be cleanly separated, so values from both caps will be displayed intertwined (unlike in Curry 9).

[Figure 2](#figure-2) is a screenshot showing an example of how the configuration could look in Curry. The idea is to use the same labels on both headboxes, but append "-2" to the labels on the second headbox.

<p align="left"><strong>Figure 2.</strong> Acquisition configuration in Curry</p>
<a id="figure-2"></a>
<p align="left">
  <img src="Acquisition configuration in Curry.png" alt="Acquisition configuration in Curry.png" width="600">
</p>


