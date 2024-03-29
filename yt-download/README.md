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

        $ ./python yt-download.py --quality 720p --url https://www.youtube.com/playlist?list=bebebe --no-meta
        $ ./python yt-download.py --url https://www.youtube.com/playlist?list=blablabla --meta

### Known issues

All the issues above seem to be PyTube problems only. I think it's worth considering something more reliable.

##### could not find match for multiple (fixed)

As of April 2022, there were some breaking updates of the YT and you may face errors like

        pytube.exceptions.RegexMatchError: get_throttling_function_name: could not find match for multiple

There are no fixes yet in the pytube 12.0.0, so temporarily you can patch the pytube package directly:

-  go to **cipher.py**

-  on line 264 fix **function_patterns()** to this:

        r'a\.[a-zA-Z]\s*&&\s*\([a-z]\s*=\s*a\.get\("n"\)\)\s*&&\s*'
        r'\([a-z]\s*=\s*([a-zA-Z0-9$]{2,3})(\[\d+\])?\([a-z]\)'

- on line 288 fix **nfunc** assignment:

        nfunc=re.escape(function_match.group(1))),

Thanks to Peter Guan from [SO](https://stackoverflow.com/questions/71907725/pytube-exceptions-regexmatcherror-get-throttling-function-name-could-not-find)

##### KeyError: 'streamingData'

On April 2023 authentication to YouTube seems to become mandatory. You'll be prompted to go to https://www.google.com/device with the provided code.
Only then you'll be allowed to dowload video stream.

Relevant links:

-   https://github.com/pytube/pytube/issues/1609

-   https://stackoverflow.com/questions/76129007/pytube-keyerror-streamdata-while-downloading-a-video

