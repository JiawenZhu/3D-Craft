"""Seed verified user-provided examples in local review only; never add votes."""
import time
from server.community import database
from server.config import IS_PRODUCTION
from server.game_links import verify_game_url

EXAMPLES = [
    ('example-moss-garden', 'Moss Robot · Sunseed Garden', 'https://moss-robot-sunseed-garden.evan001007.chatgpt.site/'),
    ('example-dragon-flight', 'Emberwing · Dragon Flight', 'https://emberwing-dragon-flight.evan001007.chatgpt.site/'),
    ('example-moonrun', 'Moonrun · Fox of the Hollow Road', 'https://claude.ai/code/artifact/b996c58b-bb3c-491c-9fd7-cc5f50a8b168'),
]

def main():
    if IS_PRODUCTION:
        raise RuntimeError('Example seeding is for local review only.')
    for game_id, title, link in EXAMPLES:
        url = verify_game_url(link)['url']
        with database() as connection:
            now = time.time()
            connection.execute('INSERT OR IGNORE INTO community_games VALUES(?,?,?,?,?,?,?,?,1,0)',
                (game_id, 'local-review-examples', title, '3D Craft examples',
                 'A playable example for local community testing.', url, now, now))
        print(title + ': available for local review')

if __name__ == '__main__':
    main()
