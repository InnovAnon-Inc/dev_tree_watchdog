import os
import time
import logging
from pathlib import Path
from git import Repo, exc
from github import Github, GithubException
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from dotenv import load_dotenv

# --- CONFIG ---

logging.basicConfig(level=logging.INFO, format='%(asctime)s | %(levelname)s | %(message)s')

class GitManager:
    def __init__(self, path: Path, token: str, org: str):
        self.path = path
        self.name = path.name
        self.token = token
        self.org_name = org
        self.gh = Github(token)
        self.repo = None

    def provision(self):
        """Ensures GitHub repo exists and local git is initialized/linked."""
        logging.info(f"🧐 Provisioning {self.name}...")
        
        # 1. Handle Remote (PyGithub)
        try:
            org = self.gh.get_organization(self.org_name)
            try:
                remote_repo = org.get_repo(self.name)
                logging.info(f"🌐 Remote exists: {remote_repo.full_name}")
            except GithubException:
                logging.info(f"🏗️ Creating private repo: {self.org_name}/{self.name}")
                remote_repo = org.create_repo(self.name, private=True)
            
            remote_url = remote_repo.clone_url.replace("https://", f"https://{self.token}@")
        except Exception as e:
            logging.error(f"❌ GitHub API Error: {e}")
            return False

        # 2. Handle Local (GitPython)
        try:
            if not (self.path / ".git").exists():
                logging.info(f"📥 Initializing local repo at {self.path}")
                self.repo = Repo.init(self.path)
            else:
                self.repo = Repo(self.path)

            # Ensure 'origin' exists
            if 'origin' not in self.repo.remotes:
                self.repo.create_remote('origin', remote_url)
            else:
                self.repo.remotes.origin.set_url(remote_url)

            # Safety Commit (Prevent headless)
            if not self.repo.heads:
                readme = self.path / "README.md"
                if not readme.exists():
                    readme.write_text(f"# {self.name}")
                self.repo.index.add(["README.md"])
                self.repo.index.commit("initial sequence")
                self.repo.git.push("-u", "origin", "master") # or main
            
            return True
        except Exception as e:
            logging.error(f"❌ Local Git Error: {e}")
            return False

class RepoSupervisor(FileSystemEventHandler):
    def __init__(self, github_token, org_name):
        self.managed_paths = {}
        self.github_token = github_token
        self.org_name = org_name

    def on_created(self, event):
        if event.is_directory:
            # Settle time for OS
            time.sleep(1)
            self.process_directory(Path(event.src_path))

    def process_directory(self, path: Path):
        path = path.resolve()
        if path in self.managed_paths or path.name.startswith('.'):
            return

        manager = GitManager(path, self.github_token, self.org_name)
        if manager.provision():
            logging.info(f"🚀 {path.name} is ready for sync.")
            # We still use gitwatch for the background filesystem-to-commit loop
            # because it's a highly optimized C/Bash utility for inotify.
            self.spawn_gitwatch(path)

    def spawn_gitwatch(self, path):
        import subprocess
        # Gitwatch is better handled as a separate process to avoid GIL issues 
        # when watching hundreds of files in Python.
        proc = subprocess.Popen(
            ["gitwatch", "-r", "origin", "-b", "main", "."],
            cwd=str(path),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE
        )
        self.managed_paths[path] = proc

def main():
    load_dotenv()
    WATCH_PATH = os.getenv("WATCH_PATH", "/mnt/dev_tree")
    GITHUB_TOKEN = os.getenv("GH_TOKEN") # Required for PyGithub
    ORG_NAME = os.getenv("ORG_NAME", "Innovanon-Inc")

    if not GITHUB_TOKEN:
        print("❌ Error: GH_TOKEN environment variable is not set.")
        exit(1)

    supervisor = RepoSupervisor(github_token=GITHUB_TOKEN, org_name=ORG_NAME)
    
    # Bootstrap existing
    for item in Path(WATCH_PATH).iterdir():
        if item.is_dir():
            supervisor.process_directory(item)

    observer = Observer()
    observer.schedule(supervisor, WATCH_PATH, recursive=False)
    observer.start()
    
    logging.info(f"🕵️ Supervisor watching {WATCH_PATH}")
    try:
        while True:
            time.sleep(10)
            # Health check logic here
    except KeyboardInterrupt:
        observer.stop()
    observer.join()

