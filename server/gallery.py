"""Loopback production metadata for reviewed gallery examples.

No generation is initiated here. The sample script annotates only an existing
asset whose immutable submission marker and copied concept both match.
"""
import hashlib
import re
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field
from typing import Literal
from . import jobs
from .config import STORAGE

router = APIRouter(tags=["Local gallery production"])


class ExampleProvenance(BaseModel):
    batchId: str = Field(pattern=r"^[a-z0-9][a-z0-9-]{1,80}$")
    slug: str = Field(pattern=r"^[a-z0-9][a-z0-9-]{1,63}$")
    conceptSha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    description: str = Field(min_length=1, max_length=500)


class GalleryAnnotation(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    kind: Literal["character", "vehicle", "flying", "prop", "world"]
    description: str = Field(min_length=1, max_length=500)
    sourceImageUrl: str = Field(min_length=1, max_length=200)
    galleryExample: ExampleProvenance


@router.post("/api/assets/{asset_id}/gallery-example")
def annotate(asset_id: str, body: GalleryAnnotation, request: Request):
    if not request.client or request.client.host not in ("127.0.0.1", "::1", "testclient"):
        raise HTTPException(403, "Gallery production is available only over loopback.")
    asset = next((item for item in jobs.list_assets() if item["id"] == asset_id), None)
    if not asset:
        raise HTTPException(404, "No such asset")
    proof = body.galleryExample
    if asset.get("sourceRef") != f"gallery:{proof.batchId}:{proof.slug}":
        raise HTTPException(409, "Gallery metadata does not match this asset's original submission.")
    expected_url = f"/files/gallery-samples/{proof.slug}.png"
    if body.sourceImageUrl != expected_url:
        raise HTTPException(400, "Gallery concepts must use the approved source-image path.")
    source = STORAGE / "gallery-samples" / f"{proof.slug}.png"
    if not source.is_file() or source.is_symlink() or not source.resolve().is_relative_to(STORAGE.resolve()):
        raise HTTPException(404, "The source concept is missing")
    if hashlib.sha256(source.read_bytes()).hexdigest() != proof.conceptSha256:
        raise HTTPException(409, "The source concept differs from the submitted image.")
    jobs.annotate_asset(asset_id, {**body.model_dump(), "author": "3D Craft", "visibility": "public"})
    return {"id": asset_id, "annotated": True}
