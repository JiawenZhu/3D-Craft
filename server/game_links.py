"""Small public HTTPS page checker; never sends studio/user credentials.
DNS results are validated and the connection is pinned to a validated address,
including every redirect. This checks reachability, not gameplay quality.
"""
import http.client
import ipaddress
import socket
import ssl
import re
from urllib.parse import urlsplit, urlunsplit, urljoin

class LinkError(ValueError):
    pass

def normalize_url(value):
    value = value.strip()
    if len(value) > 2048 or any(ord(c) < 33 for c in value) or '\\' in value:
        raise LinkError('Enter a valid public HTTPS game link.')
    try:
        parts = urlsplit(value)
        host = (parts.hostname or '').encode('idna').decode().lower().rstrip('.')
        if parts.scheme.lower() != 'https' or not host or parts.username or parts.password or parts.port not in (None, 443):
            raise ValueError()
    except (ValueError, UnicodeError):
        raise LinkError('Use a public HTTPS game link without a password or custom port.')
    if host == 'localhost' or host.endswith(('.localhost', '.local', '.internal')):
        raise LinkError('Local computer links cannot be opened by other players. Publish your game first.')
    try:
        if not ipaddress.ip_address(host).is_global:
            raise LinkError('Use a public game link, not a private network address.')
    except ValueError as error:
        if isinstance(error, LinkError):
            raise
    netloc = '[' + host + ']' if ':' in host else host
    return urlunsplit(('https', netloc, parts.path or '/', parts.query, parts.fragment))

def public_addresses(host):
    try:
        addresses = list(dict.fromkeys(info[4][0] for info in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)))
    except OSError:
        raise LinkError('This game address could not be found. Check the link and try again.')
    if not addresses or any(not ipaddress.ip_address(address).is_global for address in addresses):
        raise LinkError('The game link must resolve only to public internet addresses.')
    return addresses

class PublicHTTPS(http.client.HTTPSConnection):
    def __init__(self, host, address):
        super().__init__(host, timeout=5, context=ssl.create_default_context())
        self.address = address
    def connect(self):
        raw = socket.create_connection((self.address, 443), self.timeout)
        try:
            self.sock = self._context.wrap_socket(raw, server_hostname=self.host)
        except Exception:
            raw.close()
            raise

def fetch_page(url):
    parts = urlsplit(url)
    addresses = public_addresses(parts.hostname)
    connection = PublicHTTPS(parts.hostname, addresses[0])
    try:
        path = urlunsplit(('', '', parts.path or '/', parts.query, ''))
        connection.request('GET', path, headers={'User-Agent':'3DCraft-Game-Link-Check/1.0', 'Accept':'text/html', 'Accept-Encoding':'identity'})
        response = connection.getresponse()
        return response.status, dict((k.lower(), v) for k, v in response.getheaders()), response.read(32_768).decode('utf-8', errors='replace')
    except (OSError, http.client.HTTPException, UnicodeError):
        raise LinkError('The game page did not respond. Publish it publicly and try again.')
    finally:
        connection.close()

def verify_game_url(value):
    url = normalize_url(value)
    for _ in range(4):
        parts = urlsplit(url)
        # A shared conversation or builder workspace is not a published game.
        artifact = parts.hostname in ('claude.ai','www.claude.ai') and bool(re.fullmatch(r'/(?:artifact|code/artifact|public/artifacts)/[A-Za-z0-9_-]+/?', parts.path))
        if parts.hostname in ('claude.ai','www.claude.ai','chatgpt.com','www.chatgpt.com') and not artifact:
            raise LinkError('This is an agent/share page. Use the published playable game link instead.')
        status, headers, html = fetch_page(url)
        if status in (301,302,303,307,308):
            if not headers.get('location'):
                raise LinkError('This game link has an incomplete redirect.')
            url = normalize_url(urljoin(url, headers['location']))
            continue
        if status == 403 and artifact:
            # Claude may block data-center checks even for public artifacts.
            # Admit only to the private review queue, never claim reachability.
            return {'url': url, 'status': 'browser_review_required'}
        if status != 200:
            raise LinkError('The game page is unavailable or needs sign-in (HTTP %s). Use a public playable link.' % status)
        if 'text/html' not in headers.get('content-type','').lower():
            raise LinkError('This link is a file, not a browser game page. Use the game’s published page.')
        lower = html.lower()
        if any(marker in lower for marker in ('<title>sign in', '<title>log in', '<title>just a moment', '<title>access denied')):
            raise LinkError('This page requires sign-in or a browser access check. Use a publicly accessible game link.')
        return {'url':url, 'status':'reachable'}
    raise LinkError('This game link redirects too many times. Use its final published address.')
