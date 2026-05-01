# SetsRepsWheels

A practical workout tracker for iPhone, available in the Apple App Store as **SetsRepsWheels**.

Source: https://github.com/dutch-rob/workout_aicode

---

<!-- INFO_SCREEN_START -->
## Intro

I made this app to log sets and reps during a workout more conveniently than I have found in other apps: The sets of an exercise are on one screen, and it uses the picker wheels to set the numbers to log. The picker wheels start at the numbers of the previous time you logged the exercise.

The app is rather bare-bones. I made it first for myself and I think it works great for me. I hope that you will find it useful as well, but it is probably not the best workout app for everybody.

You will have to define your own exercises and workouts, and I will explain below how simple that goes.

Your exercises are logged on your phone and you can download or email everything you logged to yourself from the phone. You can read that file easily into a spreadsheet for further analysis.

Another practical quirk: If the machine you want to use next is in use then you can swipe through the exercises you have not logged yet during your current workout.

## Start

When you download and open the app for the first time, there will be no workouts and exercises defined yet: You need to do that yourself.

It seems best to start with clicking on the button 'new workout'. This opens the 'edit workout' screen. It seems best to first give a name to the new workout. Then, because you have not defined any exercises yet, click on the button 'new exercise'. This opens the 'edit exercise' screen where you can set the number of sets for your exercise, the lowest weight you use for this exercise as well as the highest, and the increments of the weights that the wheel switches through. With the back button, you can go back to the edit workout screen and add more exercises to your workout. After finishing the definition of your workout you go back to the start screen. You should see the name of your defined workout on that screen. If you click on it, you can start logging your exercises.

## Log exercises

From the start screen, click on the workout you want to do. This will pull up the first exercise that you defined in your workout and show the wheels for each set of your exercise: The top wheels show the weights and the bottom wheels show the number of repetitions. If you have logged the exercise before, the wheels will start off at the numbers that you logged the last time you did the exercise.

After you've done your exercise, you can click on the button 'log, next' — that will log the exercise. You can also click on 'quit' which will end the exercise as well as the workout without logging the exercise on screen.

If you want to skip the exercise, for example because the machine is in use, then you can swipe to the left to go to the next exercise that you have not logged yet in your list of exercises. You can also swipe right to the previous exercise that you have not logged yet. Swiping left/right will leave the current exercise without logging it.

If you click 'log, next' on the last exercise of your workout, a menu pops up, asking if you want to go to a next exercise and overwrite what you logged earlier for that exercise; view your workout and go back to the start screen; or go to a next exercise to look at what you logged during this workout, without changing your log.

## Edit workouts

After you've added at least one workout and one exercise, the start screen changes a bit: the button 'new workout' changes to 'edit workouts' and the button 'new exercise' changes to 'edit exercises'.

When clicking on 'edit workouts', you will see a list of the workouts that you have defined. You can click on a workout to edit the exercises that are in the workout. There you can define a new exercise ('new exercise') or add an exercise to the list of exercises of the workout by selecting from the list of all defined exercises ('Add exercise'). You can also click on 'reorder exercises' in case you want to change the order in which your exercises are presented during this workout by dragging an exercise with your finger on the icon with the three horizontal dashes on the right-hand side. You can also click on the red icon to the left of the name of an exercise in order to delete the exercise from this workout.

Back in 'edit workouts' you can also click to reorder workouts, and on the red icon to the left of the name of a workout in order to delete the workout.

## Edit exercises

From the start screen, you can also click on the button 'edit exercises'. This will show a list of the exercises that you have defined either through this button or when you were defining your workouts by adding a new exercise.

## Log screen and file

The button 'logs' takes you to a screen that displays your log entries from most recent, down to older. A logged weight is green if it is larger than the weight in the previous log of the exercise and corresponding set, and red if it is smaller. A logged number of repetitions is green if it is larger than the reps in the previous log of the exercise and corresponding set, and the corresponding weight is not smaller; it is red if the reps number is smaller and the corresponding weight is not larger.

The log screen includes buttons for exporting your log data as tab delimited file (TSV), e.g. for reading into a spreadsheet; or export log data, and workout and exercise definitions as JSON file; you can also import a JSON file that should have the correct format (seems easiest to achieve by editing a file you exported earlier - but editing a JSON is not everybody's cup of tea); and you can restore the previous JSON if your upload is not good. Export files are sent to a destination of your choice. The JSON file is now the only way to correct errors or make changes in your log. After importing a JSON file you can replace the app's data or merge with the app's data.

## Notes

1. This version of the app saves data on your iPhone (or iPad) and does not share among different devices that you may have. I am looking into how to make it possible to share among your devices.
2. This app is free and open source. You can find the open source of the app on GitHub:
   https://github.com/dutch-rob/workout_aicode
3. You are quite welcome to provide any feedback in your review comments in the App Store, or go to GitHub and provide your comments there. Perhaps you even want to do a pull request for improvements of the code. Here are a few examples for feedback:
   - Did anything go wrong? (Please specify.)
   - Do you need to share data among your devices?
   - Do you think that the app needs to log something else as well?
   - Changes to the log screen or log export?
   - Statistics for trends or so?
<!-- INFO_SCREEN_END -->
