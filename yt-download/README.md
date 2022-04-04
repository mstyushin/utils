Download YouTube playlists
--------------------------
Trivial  script for downloading youtube videos from playlist.
You may use either full playlist url or just its ID.

### Requirements
Use requirements.txt to get all the libraries needed.

-   python >= 3.7

-   pip >= 20.0

### Overview

By default it downloads 480p mp4 video. You may set desired quality with `--quality` argument.
All videos (along with some meta info) will be downloaded to `./downloads`. Change this directory with `--destination` argument.

##### Examples:

        $ ./python yt-download.py --quality 720p --url https://www.youtube.com/playlist?list=bebebe
        $ ./python yt-download.py --url https://www.youtube.com/playlist?list=blablabla
