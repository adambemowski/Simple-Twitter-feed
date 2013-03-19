Simple-Twitter-feed
===================

Basic Twitter iOS client.  The app includes the following functionality:

    Allows a user to authenticate via Twitter
    Displays a user's home_timeline, updating live whenever new tweets come in
    Allows the user to post a new tweet

From a technological perspective it includes the following:

    The app stores existing tweets in Core Data.  In such a way, if one opens the app without an Internet connection, it is still possible to see your previous tweets even if the new ones can't be downloaded.
    The app downloads new tweets on a background thread so that the UI is still responsive during the download.  Also, the app does not fully rewrite the Core Data database whenever new tweets come in.  Instead, new tweets are merged with existing tweets (and the oldest tweets are purged, if necessary for the performance reasons).

NOTE: The goal of this sample project was to have a functioning app, so not much care was given to the UI/UX.  For example no Twitter profile pictures next to tweets, no support to both iPhone 4/4S and iPhone 5 layouts (just picked one), etc.
