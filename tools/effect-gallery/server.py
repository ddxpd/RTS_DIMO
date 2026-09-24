from __future__ import annotations

import argparse
import json
import shutil
import uuid
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path, PurePosixPath
from urllib.parse import parse_qs, urlsplit


ROOT = Path(__file__).resolve().parent
TRASH_DIR = ROOT / ".trash"
LIBRARY_DIR = ROOT / "library"
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}


def clean_relative(value: str, *, allow_trash: bool = False) -> tuple[Path, str]:
    normalized = str(value or "").replace("\\", "/")
    relative = PurePosixPath(normalized)
    if not normalized or relative.is_absolute() or ".." in relative.parts:
        raise ValueError("invalid relative path")
    if any(part in {"", "."} for part in relative.parts):
        raise ValueError("invalid relative path")
    relative_text = relative.as_posix()
    if not allow_trash and (relative_text == ".trash" or relative_text.startswith(".trash/")):
        raise ValueError("reserved trash path")
    resolved = (ROOT / Path(*relative.parts)).resolve()
    try:
        resolved.relative_to(ROOT.resolve())
    except ValueError as error:
        raise ValueError("path escapes gallery root") from error
    return resolved, relative_text


def image_extension(name: str) -> str:
    extension = Path(name).suffix.lower()
    if extension not in IMAGE_EXTENSIONS:
        raise ValueError("unsupported image type")
    return extension


class GalleryHandler(SimpleHTTPRequestHandler):
    server_version = "IronFrontGallery/1.0"

    def __init__(self, *args, directory: str | None = None, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self) -> None:
        split = urlsplit(self.path)
        if split.path == "/api/health":
            return self.send_json({"ok": True})
        if split.path == "/api/generated":
            return self.send_json({"files": self.generated_files()})
        super().do_GET()

    def do_POST(self) -> None:
        split = urlsplit(self.path)
        try:
            if split.path == "/api/import":
                return self.import_file(parse_qs(split.query).get("name", [""])[0])
            payload = self.read_json()
            if split.path == "/api/trash":
                return self.trash_file(str(payload.get("path", "")))
            if split.path == "/api/restore":
                return self.restore_file(
                    str(payload.get("trash_path", "")),
                    str(payload.get("original_path", "")),
                )
            if split.path == "/api/permanent-delete":
                return self.permanent_delete(str(payload.get("trash_path", "")))
            self.send_error(404, "unknown API endpoint")
        except ValueError as error:
            self.send_json({"error": str(error)}, status=400)
        except FileNotFoundError:
            self.send_json({"error": "file not found"}, status=404)
        except OSError as error:
            self.send_json({"error": str(error)}, status=500)

    def translate_path(self, path: str) -> str:
        translated = Path(super().translate_path(path)).resolve()
        try:
            translated.relative_to(TRASH_DIR.resolve())
        except ValueError:
            return str(translated)
        return str(ROOT / "__missing_trash_file__")

    def read_json(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as error:
            raise ValueError("invalid content length") from error
        if length <= 0 or length > 1024 * 1024:
            raise ValueError("invalid JSON body")
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ValueError("invalid JSON body") from error
        if not isinstance(payload, dict):
            raise ValueError("JSON body must be an object")
        return payload

    def read_body(self) -> bytes:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as error:
            raise ValueError("invalid content length") from error
        if length <= 0 or length > 512 * 1024 * 1024:
            raise ValueError("invalid file body")
        return self.rfile.read(length)

    def import_file(self, name: str) -> None:
        extension = image_extension(name)
        body = self.read_body()
        if not body:
            raise ValueError("empty image body")
        LIBRARY_DIR.mkdir(parents=True, exist_ok=True)
        safe_name = "".join(character for character in Path(name).name if character.isalnum() or character in "._-")
        if not safe_name:
            safe_name = "image" + extension
        destination = LIBRARY_DIR / f"{uuid.uuid4().hex}_{safe_name}"
        destination.write_bytes(body)
        self.send_json({"path": destination.relative_to(ROOT).as_posix(), "size": len(body)})

    def trash_file(self, source_path: str) -> None:
        source, relative_text = clean_relative(source_path)
        if not source.is_file():
            raise FileNotFoundError(source_path)
        TRASH_DIR.mkdir(parents=True, exist_ok=True)
        destination = TRASH_DIR / f"{uuid.uuid4().hex}_{source.name}"
        shutil.move(str(source), destination)
        self.send_json(
            {
                "original_path": relative_text,
                "trash_path": destination.relative_to(ROOT).as_posix(),
            }
        )

    def restore_file(self, trash_path: str, original_path: str) -> None:
        source, trash_relative = clean_relative(trash_path, allow_trash=True)
        destination, original_relative = clean_relative(original_path)
        if not trash_relative.startswith(".trash/") or not source.is_file():
            raise FileNotFoundError(trash_path)
        if destination.exists():
            raise ValueError("original path already exists")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source), destination)
        self.send_json(
            {"original_path": original_relative, "trash_path": trash_relative}
        )

    def permanent_delete(self, trash_path: str) -> None:
        source, trash_relative = clean_relative(trash_path, allow_trash=True)
        if not trash_relative.startswith(".trash/") or not source.is_file():
            raise FileNotFoundError(trash_path)
        source.unlink()
        self.send_json({"trash_path": trash_relative, "deleted": True})

    def generated_files(self) -> list[dict[str, str]]:
        generated = ROOT / "generated"
        if not generated.is_dir():
            return []
        return [
            {"file": f"generated/{path.name}"}
            for path in sorted(generated.iterdir())
            if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
        ]

    def send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args) -> None:
        print(f"[gallery] {self.address_string()} - {format % args}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Local effect gallery server")
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--directory", default=str(ROOT))
    args = parser.parse_args()
    TRASH_DIR.mkdir(parents=True, exist_ok=True)
    LIBRARY_DIR.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((args.bind, args.port), GalleryHandler)
    print(f"Iron Front effect gallery: http://{args.bind}:{args.port}/")
    print(f"Serving directory: {ROOT}")
    print("Press Ctrl+C to stop the local server.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
