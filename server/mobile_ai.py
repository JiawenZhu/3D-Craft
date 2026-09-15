"""Authenticated local ChatGPT account endpoints; credentials never leave Codex."""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from . import codex_bridge, image_models
from .mobile import account

router = APIRouter(prefix="/api/mobile/ai", tags=["iOS local ChatGPT connection"])


class CancelLogin(BaseModel):
    loginId: str = Field(min_length=1, max_length=200)


def _run(action, *args):
    try:
        return action(*args)
    except codex_bridge.BridgeError as exc:
        raise HTTPException(409, str(exc)) from exc
    except OSError as exc:
        raise HTTPException(503, "The local Codex connection is unavailable.") from exc


@router.get("/account")
def status(owner=Depends(account)):
    status = codex_bridge.account_status(owner)
    return {**status, "imageModels": image_models.catalog(status)["models"]}


@router.post("/login")
def login(owner=Depends(account)):
    return _run(codex_bridge.start_login, owner)


@router.post("/login/cancel")
def cancel(body: CancelLogin, owner=Depends(account)):
    return _run(codex_bridge.cancel_login, owner, body.loginId)


@router.post("/logout")
def logout(owner=Depends(account)):
    return _run(codex_bridge.logout, owner)
