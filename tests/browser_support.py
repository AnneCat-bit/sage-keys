"""Optional verified HTTPS transport for environments with a separate browser CA store."""
import mimetypes
import time
from urllib.error import HTTPError
from pathlib import Path
from urllib.parse import unquote, urlsplit
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]

def configure_transport(context, url, fixture=False, system_https=False):
    if not (fixture or system_https):
        return
    def serve(route):
        request = route.request
        if request.method != 'GET' or not request.url.startswith(url):
            return route.abort()
        if fixture:
            relative = unquote(urlsplit(request.url).path[len(urlsplit(url).path):])
            candidate = (ROOT/(relative or 'index.html')).resolve()
            if ROOT not in candidate.parents or not candidate.is_file():
                return route.fulfill(status=404,body='Not found')
            return route.fulfill(path=str(candidate),content_type=mimetypes.guess_type(candidate)[0] or 'application/octet-stream')
        for attempt in range(3):
            try:
                response = urlopen(request.url,timeout=20)
            except HTTPError as error:
                if attempt < 2 and error.code in (502,503,504):
                    error.close()
                    time.sleep(1+attempt)
                    continue
                response = error
            with response:
                return route.fulfill(status=response.status,headers=dict(response.headers),body=response.read())
    context.route('**/*',serve)
