import sys
import time
import traceback
import re
import json
import os
import logging
from pytube import YouTube, Playlist
from pytube.exceptions import VideoUnavailable
from retrying import retry

from argparse import ArgumentParser

logging.basicConfig()
log = logging.getLogger('yt-download')
log.setLevel(logging.INFO)
VIDEO_TYPE = 'mp4'


def on_exception(ex):
    log.info("Got exception", ex)
    input("It seems it failed with exception")
    return True


#@retry(wait_fixed=5000, retry_on_exception=on_exception)
def download_youtube(url, mediafolder, mediafilename, quality):
    video_stream = YouTube(url, use_oauth=True, allow_oauth_cache=True).streams.filter(subtype=VIDEO_TYPE, res=quality).first()
    video_stream.download(mediafolder, mediafilename + '.' + VIDEO_TYPE)


#@retry(wait_fixed=5000, retry_on_exception=on_exception)
def grab_video_info(idx, video_url, downloader, quality, video_type=VIDEO_TYPE):
    try:
        video = YouTube(video_url, use_oauth=True, allow_oauth_cache=True)
        video_stream = video.streams.filter(subtype=video_type, res=quality).first()
        log.info(f"Get information about {video_stream.title}")
        return ({
                    "name": normalize(video_stream.title),
                    "description": f"f{video.description}",
                    "source": f"{video_url}"
                },
                video_url,
                downloader)
    except VideoUnavailable:
        log.error(f"Video {idx}:{video_url} unavailable")
    return None


def normalize(s: str):
    rx = re.compile(r'_{2,}')
    normalized = s.lower()\
                .replace('-', '_')\
                .replace(' ', '_')\
                .replace('.', '_')\
                .replace(',', '_')\
                .replace("'", '')\
                .replace('|', '')
    return rx.sub('_', normalized)


def grab_youtube_playlist(playlist_url, quality, start_from=0):
    result = []
    playlist = Playlist(playlist_url)

    # hack from https://stackoverflow.com/questions/62661930/pytube3-playlist-returns-empty-list
    playlist._video_regex = re.compile(r"\"url\":\"(/watch\?v=[\w-]*)")

    video_urls = list(playlist.video_urls)
    video_urls.sort()
    for idx, video_url in enumerate(video_urls[start_from:]):
        log.info(f'processing video url: {video_url}')
        video_info = grab_video_info(idx, video_url, download_youtube, quality)
        if video_info:
            result.append(video_info)
    return result


if __name__ == '__main__':
    try:
        parser = ArgumentParser(description="""\r
Download YouTube playlists easily!\r
                                """)

        parser.add_argument('--url',
                            dest='url',
                            help='URL of the YouTube playlist',
                            required=True)
        parser.add_argument('--quality',
                            dest='quality',
                            help='Preferred quality of video to download. Default: 480p',
                            default='480p')
        parser.add_argument('--destination',
                            dest='destination',
                            help='Path to the destination directory where to put dowloaded media. Default: ./downloads',
                            default='./downloads')
        parser.add_argument('--meta',
                            help='Whether to store metadata info.',
                            action='store_true')
        parser.add_argument('--no-meta',
                            help='Whether to store metadata info.',
                            dest='meta',
                            action='store_false')
        parser.set_defaults(meta=False)

        args = parser.parse_args()
        log.info(f'Downloading playlist {args.url}')

        for (meta, video, downloader) in grab_youtube_playlist(args.url, args.quality):
            dst_dir = os.path.abspath(args.destination)
            if not os.path.isdir(dst_dir):
                os.mkdir(dst_dir)
            if args.meta:
                metafile_path = os.path.join(dst_dir, meta['name']+".meta.json")
                with open(metafile_path, "w") as metafile:
                    log.info(f"Store meta for {meta['name']}")
                    metafile.write(json.dumps(meta))
            log.info(f"Store media for {meta['name']}")
            if video:
                downloader(video, dst_dir, meta['name'], args.quality)
            time.sleep(1)

    except KeyboardInterrupt:
        print('Got SIGINT, terminating')
        time.sleep(0.2)
        sys.exit(0)
    except Exception:
        print('Something went wrong, see traceback below')
        traceback.print_exc()
        sys.exit(1)
