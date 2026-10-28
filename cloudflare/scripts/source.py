"""Build the exact deployable AGPL source offer; never bundle secrets or local DB."""
from pathlib import Path
import tarfile
root = Path(__file__).resolve().parents[1]
(root / 'public').mkdir(exist_ok=True)
with tarfile.open(root / 'public/source.tar.gz', 'w:gz') as archive:
    for name in ('src','migrations','scripts','tests','package.json','package-lock.json','wrangler.jsonc','README.md','GITHUB_DEPLOY.md','setup.sh','.node-version','LICENSE','.gitignore'):
        path = root / name
        if path.exists():
            archive.add(path, arcname='cloudflare/' + name)
    archive.add(root.parent / 'NOTICE.md', arcname='NOTICE.md')
