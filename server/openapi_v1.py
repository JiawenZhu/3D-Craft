"""OpenAPI 3.1 specification for 3D Craft External Agent API (v1).

Defines complete parameters, request bodies, and responses for external
coding agents (Claude, ChatGPT, Muse, or custom automation tools).
"""
from typing import Any, Dict

MODEL_ENGINES = [
    'tripo', 'seed3d', 'hunyuan-rapid', 'hunyuan-pro',
    'hi3d-fast', 'hi3d-pro', 'hi3d-quality', 'hi3d-master',
    'meshy-single', 'meshy-multi',
    'rodin', 'trellis-2', 'hunyuan3d-2.1', 'hunyuan3d-2-white',
]
ANIMATION_MODELS = [
    'atlas-seedance-2.0-mini', 'atlas-seedance-2.0', 'atlas-seedance-2.5',
    'atlas-minimax-h3', 'atlas-wan-3.0-prime', 'seedance-2.5', 'minimax-h3',
]
ANIMATION_RESOLUTIONS = ['480p', '720p', '768p', '2K']


def get_openapi_v1_spec() -> Dict[str, Any]:
    spec = {
        "openapi": "3.1.0",
        "info": {
            "title": "3D Craft External Agent Pipeline API",
            "version": "1.0.0",
            "description": (
                "User-authorized REST API for third-party AI agents and client applications "
                "to interact with 3D Craft's prompt planning, concept generation, and 3D reconstruction pipeline. "
                "All actions spend Tokens from the authorizing user's 3D Craft production wallet."
            ),
        },
        "servers": [
            {
                "url": "https://3d-craft.web.app",
                "description": "3D Craft Production Cloud API",
            }
        ],
        "components": {
            "securitySchemes": {
                "ApiKeyAuth": {
                    "type": "http",
                    "scheme": "bearer",
                    "bearerFormat": "craft_live_*",
                    "description": (
                        "High-entropy bearer key generated in 3D Craft Profile Credentials. "
                        "Must begin with 'craft_live_' prefix."
                    ),
                }
            },
            "schemas": {
                "WalletResponse": {
                    "type": "object",
                    "required": ["available", "packAvailable", "subscriptionAvailable", "reserved", "environment"],
                    "properties": {
                        "available": {"type": "integer", "description": "Total spendable Tokens"},
                        "packAvailable": {"type": "integer", "description": "Tokens from purchased packs"},
                        "subscriptionAvailable": {"type": "integer", "description": "Tokens from active subscription allowance"},
                        "subscriptionProduct": {"type": "string", "nullable": True},
                        "subscriptionExpiresAt": {"type": "number", "nullable": True},
                        "reserved": {"type": "integer", "description": "Tokens currently locked for in-flight jobs"},
                        "freeConceptTokens": {"type": "integer"},
                        "environment": {"type": "string", "enum": ["PRODUCTION"], "description": "Always PRODUCTION for API keys"},
                        "ledger": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "id": {"type": "string"},
                                    "amount": {"type": "integer"},
                                    "kind": {"type": "string"},
                                    "createdAt": {"type": "number"},
                                },
                            },
                        },
                    },
                },
                "ConceptRequest": {
                    "type": "object",
                    "required": ["idempotencyKey", "maxTokens"],
                    "properties": {
                        "idempotencyKey": {
                            "type": "string",
                            "minLength": 8,
                            "maxLength": 120,
                            "description": "Unique client UUID or idempotency token to prevent duplicate charges",
                        },
                        "count": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 4,
                            "default": 1,
                            "description": "Number of concept image variations to generate",
                        },
                        "prompt": {
                            "type": "string",
                            "maxLength": 4000,
                            "default": "",
                            "description": "Creative concept description",
                        },
                        "imageModel": {
                            "type": "string",
                            "enum": ["gemini-3-pro-image", "gemini-3.1-flash-image"],
                            "default": "gemini-3-pro-image",
                        },
                        "plannerModel": {
                            "type": "string",
                            "enum": ["gemini-3.5-flash-lite", "gemini-3.8-flash"],
                            "default": "gemini-3.5-flash-lite",
                        },
                        "plannerEffort": {
                            "type": "string",
                            "enum": ["low"],
                            "default": "low",
                        },
                        "preserveReference": {"type": "boolean", "default": False},
                        "referenceId": {"type": "string", "nullable": True, "maxLength": 150},
                        "style": {"type": "string", "nullable": True, "maxLength": 100},
                        "maxTokens": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 200,
                            "description": "Maximum Tokens caller authorizes for this generation step",
                        },
                    },
                },
                "ModelRequest": {
                    "type": "object",
                    "required": ["idempotencyKey"],
                    "properties": {
                        "idempotencyKey": {
                            "type": "string",
                            "minLength": 8,
                            "maxLength": 120,
                            "description": "Unique client token preventing duplicate charged reconstruction",
                        },
                        "engine": {
                            "type": "string",
                            "enum": MODEL_ENGINES,
                            "default": "tripo",
                        },
                        "quality": {
                            "type": "string",
                            "enum": ["default", "speedy"],
                            "default": "default",
                        },
                        "effort": {
                            "type": "string",
                            "enum": ["extreme-low", "low", "medium", "high", "extreme-high"],
                            "default": "high",
                        },
                        "modelPrompt": {"type": "string", "nullable": True, "maxLength": 800},
                        "conceptIds": {
                            "type": "array",
                            "items": {"type": "string"},
                            "minItems": 1,
                            "maxItems": 4,
                            "nullable": True,
                        },
                    },
                },
                "PromptRequest": {
                    "type": "object",
                    "required": ["idempotencyKey", "maxTokens"],
                    "properties": {
                        "idempotencyKey": {"type": "string", "minLength": 8, "maxLength": 120},
                        "prompt": {"type": "string", "maxLength": 4000, "default": ""},
                        "plannerModel": {"type": "string", "enum": ["gemini-3.5-flash-lite", "gemini-3.8-flash"], "default": "gemini-3.5-flash-lite"},
                        "plannerEffort": {"type": "string", "enum": ["low", "medium", "high"], "default": "low"},
                        "maxTokens": {"type": "integer", "minimum": 1, "maximum": 100},
                    },
                },
                "ChatRequest": {
                    "type": "object",
                    "required": ["clientId", "text", "maxTokens"],
                    "properties": {
                        "clientId": {"type": "string", "minLength": 8, "maxLength": 120},
                        "text": {"type": "string", "minLength": 1, "maxLength": 4000},
                        "plannerModel": {"type": "string", "enum": ["gemini-3.5-flash-lite", "gemini-3.8-flash"], "default": "gemini-3.5-flash-lite"},
                        "plannerEffort": {"type": "string", "enum": ["low", "medium", "high"], "default": "low"},
                        "conceptId": {"type": "string", "nullable": True, "maxLength": 150},
                        "style": {"type": "string", "default": "Stylized", "maxLength": 100},
                        "maxTokens": {"type": "integer", "minimum": 1, "maximum": 100},
                    },
                },
                "AssetItem": {
                    "type": "object",
                    "required": ["id", "name"],
                    "properties": {
                        "id": {"type": "string"},
                        "name": {"type": "string"},
                        "kind": {"type": "string", "enum": ["model", "animation", "concept"]},
                        "engine": {"type": "string", "nullable": True, "description": "Image-to-3D engine for newly created models"},
                        "model": {"type": "string", "nullable": True, "description": "Animation model for newly created videos"},
                        "modelUrl": {"type": "string", "nullable": True, "description": "Cloud storage media URL"},
                        "videoUrl": {"type": "string", "nullable": True},
                        "downloadUrl": {"type": "string", "nullable": True, "description": "Bearer-key authorized GLB, MP4, or image download endpoint"},
                        "thumbUrl": {"type": "string", "nullable": True},
                        "isExample": {"type": "boolean"},
                    },
                },
                "JobDetail": {
                    "type": "object",
                    "required": ["id", "status"],
                    "properties": {
                        "id": {"type": "string"},
                        "status": {"type": "string", "enum": ["queued", "running", "done", "failed"]},
                        "progress": {"type": "number"},
                        "modelUrl": {"type": "string", "nullable": True},
                        "thumbUrl": {"type": "string", "nullable": True},
                        "createdAt": {"type": "number"},
                    },
                },
                "ErrorResponse": {
                    "type": "object",
                    "required": ["detail"],
                    "properties": {
                        "detail": {"type": "string", "description": "Human-readable error description"},
                    },
                },
            },
        },
        "security": [{"ApiKeyAuth": []}],
        "paths": {
            "/api/v1/wallet": {
                "get": {
                    "summary": "Read wallet Token balance",
                    "description": "Reads available and reserved Token balance from the production ledger.",
                    "responses": {
                        "200": {
                            "description": "Current wallet balance and ledger history",
                            "content": {"application/json": {"schema": {"$ref": "#/components/schemas/WalletResponse"}}},
                        },
                        "401": {"description": "Invalid, expired, or revoked API key"},
                        "403": {"description": "Account deleted, disabled, or missing wallet:read scope"},
                    },
                }
            },
            "/api/v1/image-models": {
                "get": {
                    "summary": "List concept generation models and token quotes",
                    "responses": {
                        "200": {"description": "Available image models and required token quotes"},
                    },
                }
            },
            "/api/v1/projects": {
                "get": {
                    "summary": "List owned projects",
                    "description": "Lists studio projects with concepts and turns.",
                    "responses": {
                        "200": {"description": "Array of projects"},
                    },
                },
                "post": {
                    "summary": "Create a new studio project",
                    "requestBody": {
                        "content": {
                            "multipart/form-data": {
                                "schema": {
                                    "type": "object",
                                    "properties": {
                                        "name": {"type": "string", "default": "Untitled idea"},
                                        "prompt": {"type": "string", "default": ""},
                                        "style": {"type": "string", "default": "Stylized"},
                                        "clientId": {"type": "string"},
                                        "image": {"type": "string", "format": "binary"},
                                    },
                                }
                            }
                        }
                    },
                    "responses": {
                        "200": {"description": "Created project metadata"},
                    },
                },
            },
            "/api/v1/projects/{project_id}/concepts": {
                "post": {
                    "summary": "Generate concept image candidates",
                    "parameters": [
                        {"name": "project_id", "in": "path", "required": True, "schema": {"type": "string"}}
                    ],
                    "requestBody": {
                        "required": True,
                        "content": {
                            "application/json": {"schema": {"$ref": "#/components/schemas/ConceptRequest"}}
                        },
                    },
                    "responses": {
                        "200": {"description": "Queued concept job and generated candidates"},
                        "409": {"description": "Idempotency key collision with differing payload"},
                    },
                }
            },
            "/api/v1/concepts/{concept_id}/refine": {
                "post": {
                    "summary": "Refine an existing concept image",
                    "parameters": [
                        {"name": "concept_id", "in": "path", "required": True, "schema": {"type": "string"}}
                    ],
                    "requestBody": {
                        "required": True,
                        "content": {
                            "application/json": {"schema": {"$ref": "#/components/schemas/ConceptRequest"}}
                        },
                    },
                    "responses": {"200": {"description": "Refined concept output"}},
                }
            },
            "/api/v1/concepts/{concept_id}/model-prompt": {
                "post": {
                    "summary": "Gemini prompt planning for 3D model generation",
                    "parameters": [
                        {"name": "concept_id", "in": "path", "required": True, "schema": {"type": "string"}}
                    ],
                    "requestBody": {
                        "required": True,
                        "content": {
                            "application/json": {"schema": {"$ref": "#/components/schemas/PromptRequest"}}
                        },
                    },
                    "responses": {"200": {"description": "Structured 3D prompt proposal"}},
                }
            },
            "/api/v1/projects/{project_id}/chat": {
                "post": {
                    "summary": "Creative thinking partner prompt chat",
                    "parameters": [
                        {"name": "project_id", "in": "path", "required": True, "schema": {"type": "string"}}
                    ],
                    "requestBody": {
                        "required": True,
                        "content": {
                            "application/json": {"schema": {"$ref": "#/components/schemas/ChatRequest"}}
                        },
                    },
                    "responses": {"200": {"description": "Assistant chat turn response"}},
                }
            },
            "/api/v1/planning/{job_id}": {
                "get": {
                    "summary": "Get status and result of a prompt planning job",
                    "parameters": [
                        {"name": "job_id", "in": "path", "required": True, "schema": {"type": "string"}}
                    ],
                    "responses": {"200": {"description": "Prompt planning output"}},
                }
            },
            "/api/v1/concepts/{concept_id}/model": {
                "post": {
                    "summary": "Generate 3D model from concept image",
                    "parameters": [
                        {"name": "concept_id", "in": "path", "required": True, "schema": {"type": "string"}}
                    ],
                    "requestBody": {
                        "required": True,
                        "content": {
                            "application/json": {"schema": {"$ref": "#/components/schemas/ModelRequest"}}
                        },
                    },
                    "responses": {
                        "200": {"description": "Job submitted and queued for cloud 3D reconstruction"}
                    },
                }
            },
            "/api/v1/jobs": {
                "get": {
                    "summary": "List all 3D reconstruction and concept jobs",
                    "responses": {"200": {"description": "List of jobs"}},
                }
            },
            "/api/v1/jobs/{ident}": {
                "get": {
                    "summary": "Get 3D reconstruction job status and model URL",
                    "parameters": [
                        {"name": "ident", "in": "path", "required": True, "schema": {"type": "string"}}
                    ],
                    "responses": {
                        "200": {
                            "description": "Job status with GLB model URL when completed",
                            "content": {"application/json": {"schema": {"$ref": "#/components/schemas/JobDetail"}}},
                        }
                    },
                }
            },
            "/api/v1/planning/prompt": {
                "post": {
                    "summary": "Gemini standalone text prompt planning for 3D model generation",
                    "description": "Generate an enhanced, production-ready 3D model prompt from a text description without needing a reference image.",
                    "requestBody": {
                        "required": True,
                        "content": {
                            "application/json": {"schema": {"$ref": "#/components/schemas/PromptRequest"}}
                        },
                    },
                    "responses": {"200": {"description": "Structured 3D prompt proposal"}},
                }
            },
            "/api/v1/assets": {
                "get": {
                    "summary": "List owned 3D objects, videos, and concept images",
                    "description": "Returns owned creations with model or animation identifiers when recorded and downloadable media URLs.",
                    "responses": {
                        "200": {
                            "description": "Owned 3D objects, videos, and concept images with media URLs",
                            "content": {
                                "application/json": {
                                    "schema": {
                                        "type": "object",
                                        "properties": {
                                            "owned": {
                                                "type": "array",
                                                "items": {"$ref": "#/components/schemas/AssetItem"},
                                            },
                                            "examples": {"type": "array"},
                                        },
                                    }
                                }
                            },
                        }
                    },
                }
            },
            "/api/v1/assets/{asset_id}/download": {
                "get": {
                    "summary": "Download 3D model, character animation video, or concept image with API key",
                    "description": (
                        "Stream the raw binary asset file directly using your Bearer API key. No Firebase ID token required. "
                        "By default (kind=auto), automatically detects whether the asset is a 3D model (GLB), character animation (MP4), "
                        "or concept image (JPEG/PNG) and streams with appropriate Content-Type."
                    ),
                    "parameters": [
                        {"name": "asset_id", "in": "path", "required": True, "schema": {"type": "string"}},
                        {
                            "name": "kind",
                            "in": "query",
                            "required": False,
                            "schema": {
                                "type": "string",
                                "enum": ["model", "preview", "video", "animation", "image", "auto"],
                                "default": "auto",
                            },
                        },
                    ],
                    "responses": {
                        "200": {
                            "description": "Binary file (video/mp4, model/gltf-binary, image/jpeg, or image/png)",
                            "content": {
                                "video/mp4": {"schema": {"type": "string", "format": "binary"}},
                                "model/gltf-binary": {"schema": {"type": "string", "format": "binary"}},
                                "image/jpeg": {"schema": {"type": "string", "format": "binary"}},
                                "image/png": {"schema": {"type": "string", "format": "binary"}},
                                "model/vnd.usdz+zip": {"schema": {"type": "string", "format": "binary"}},
                            },
                        },
                        "404": {"description": "Asset or file not found in account"},
                    },
                }
            },
        },
    }
    spec["components"]["schemas"].update(CREATION_SCHEMAS)
    spec["components"]["schemas"].update(EXTENDED_SCHEMAS)
    spec["paths"].update(CREATION_PATHS)
    spec["paths"].update(ANIMATION_PATHS)
    spec["paths"].update(EXTENDED_PATHS)
    return spec


def _id(name: str) -> Dict[str, Any]:
    return {"name": name, "in": "path", "required": True, "schema": {"type": "string"}}


def _json(ref: str) -> Dict[str, Any]:
    return {"content": {"application/json": {"schema": {"$ref": f"#/components/schemas/{ref}"}}}}


DELETE_NOTE = (
    "Permanent: records and files are erased and cannot be restored. Requires the assets:delete scope, "
    "which full access ('*') does not include. Returns 409 while a creation in the project is still running."
)

CREATION_SCHEMAS: Dict[str, Any] = {
    "CreationRequest": {
        "type": "object",
        "required": ["idempotencyKey", "maxTokens"],
        "properties": {
            "idempotencyKey": {"type": "string", "minLength": 8, "maxLength": 100,
                               "description": "Unique per creation. Retrying with the same key never charges twice."},
            "prompt": {"type": "string", "maxLength": 4000, "description": "What to create, or how to change it when reprompting."},
            "projectId": {"type": "string", "description": "Reprompt: add a new image and 3D model to this existing project."},
            "name": {"type": "string", "maxLength": 120, "description": "Project name in the app. Defaults to the prompt."},
            "style": {"type": "string", "maxLength": 100},
            "engine": {"type": "string", "enum": MODEL_ENGINES, "default": "rodin"},
            "quality": {"type": "string", "enum": ["default", "speedy"], "default": "default"},
            "effort": {"type": "string", "enum": ["extreme-low", "low", "medium", "high", "extreme-high"], "default": "high"},
            "maxTokens": {"type": "integer", "minimum": 1, "maximum": 1000,
                          "description": "Spending cap for image + 3D. Get it from GET /api/v1/creations/quote."},
        },
    },
    "CreationStatus": {
        "type": "object",
        "required": ["id", "stage", "status", "progress"],
        "properties": {
            "id": {"type": "string", "description": "Creation ID (the concept job ID)."},
            "projectId": {"type": "string"},
            "prompt": {"type": "string", "nullable": True},
            "stage": {"type": "string", "enum": ["concepts", "model", "done", "failed"]},
            "status": {"type": "string", "enum": ["queued", "running", "done", "failed"]},
            "progress": {"type": "integer", "minimum": 0, "maximum": 100},
            "message": {"type": "string", "nullable": True},
            "conceptJobId": {"type": "string"},
            "modelJobId": {"type": "string", "nullable": True},
            "concepts": {"type": "array", "items": {"type": "object", "properties": {
                "id": {"type": "string"}, "label": {"type": "string", "nullable": True},
                "imageUrl": {"type": "string", "description": "API-key download path for the image (JPEG)."}}}},
            "asset": {"type": "object", "nullable": True, "properties": {
                "id": {"type": "string"}, "downloadUrl": {"type": "string", "description": "GLB download path."},
                "previewUrl": {"type": "string"}}},
            "tokens": {"type": "integer", "description": "Tokens charged or currently reserved."},
            "error": {"type": "string", "nullable": True},
            "createdAt": {"type": "number"},
        },
    },
    "ProjectDetail": {
        "type": "object",
        "properties": {
            "id": {"type": "string"}, "name": {"type": "string"}, "prompt": {"type": "string"},
            "style": {"type": "string"}, "createdAt": {"type": "number"},
            "concepts": {"type": "array", "items": {"type": "object"}, "description": "Images; imageUrl is an API-key download path."},
            "conversation": {"type": "array", "items": {"type": "object"}},
            "jobs": {"type": "array", "items": {"type": "object"}},
            "models": {"type": "array", "items": {"type": "object"}, "description": "3D objects with downloadUrl."},
        },
    },
    "DeleteResult": {
        "type": "object",
        "required": ["deleted", "id"],
        "properties": {"deleted": {"type": "boolean"}, "id": {"type": "string"},
                       "images": {"type": "integer"}, "models": {"type": "integer"}, "jobs": {"type": "integer"}},
    },
}

ANIMATION_PATHS: Dict[str, Any] = {
    "/api/v1/animations/quote": {
        "get": {
            "summary": "Quote a character animation",
            "description": "Provider-specific Token quote for one looping clip. Choose a supported model, resolution, duration, and aspect together; unsupported combinations have no quote.",
            "parameters": [
                {"name": "model", "in": "query", "required": False, "schema": {"type": "string", "enum": ANIMATION_MODELS, "default": "seedance-2.5"}},
                {"name": "resolution", "in": "query", "required": False, "schema": {"type": "string", "enum": ANIMATION_RESOLUTIONS, "default": "480p"}},
                {"name": "duration", "in": "query", "required": False, "schema": {"type": "string", "enum": ["4", "5", "6"], "default": "4"}},
                {"name": "aspect", "in": "query", "required": False, "schema": {"type": "string", "enum": ["1:1", "16:9", "9:16"], "default": "1:1"}},
            ],
            "responses": {"200": {"description": "maxTokens, provider cost and whether the service is available"}},
        }
    },
    "/api/v1/concepts/{concept_id}/animation": {
        "post": {
            "summary": "Animate a character image into a looping clip",
            "description": (
                "Turns one of the account's images into a short silent MP4 that ends on its first frame, so it "
                "loops cleanly. Poll GET /api/v1/jobs/{id} until status is done, then download the clip from "
                "GET /api/v1/assets/{id}/download. Requires animations:write."
            ),
            "parameters": [_id("concept_id")],
            "requestBody": {"required": True, "content": {"application/json": {"schema": {
                "type": "object",
                "required": ["idempotencyKey", "maxTokens"],
                "properties": {
                    "idempotencyKey": {"type": "string", "minLength": 8, "maxLength": 120},
                    "motion": {"type": "string", "maxLength": 600,
                               "description": "What the character should do. Left out, it breathes and blinks gently."},
                    "model": {"type": "string", "enum": ANIMATION_MODELS, "default": "seedance-2.5"},
                    "resolution": {"type": "string", "enum": ANIMATION_RESOLUTIONS, "default": "480p"},
                    "duration": {"type": "string", "enum": ["4", "5", "6"], "default": "4"},
                    "aspect": {"type": "string", "enum": ["1:1", "16:9", "9:16"], "default": "1:1"},
                    "maxTokens": {"type": "integer", "minimum": 1, "maximum": 1000,
                                  "description": "Spending cap; take it from GET /api/v1/animations/quote."},
                }}}}},
            "responses": {
                "200": {"description": "Animation job accepted", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/JobDetail"}}}},
                "402": {"description": "Not enough Tokens"},
                "409": {"description": "maxTokens below the quote, or the key was used for different work"},
                "503": {"description": "Character animation is switched off"},
            },
        }
    },
}

CREATION_PATHS: Dict[str, Any] = {
    "/api/v1/creations/quote": {
        "get": {
            "summary": "Quote a one-step creation",
            "description": "Maximum Tokens for one concept image plus one 3D model. Pass maxTokens as the cap.",
            "parameters": [
                {"name": "engine", "in": "query", "required": False, "schema": {"type": "string", "enum": MODEL_ENGINES, "default": "rodin"}},
                {"name": "effort", "in": "query", "required": False, "schema": {"type": "string", "enum": ["extreme-low", "low", "medium", "high", "extreme-high"], "default": "high"}},
            ],
            "responses": {"200": {"description": "conceptTokens, modelTokens, maxTokens, expiresAt"}},
        }
    },
    "/api/v1/creations": {
        "post": {
            "summary": "Create a 3D object from a prompt in one step",
            "description": (
                "Creates the project (or reuses projectId to reprompt), generates one concept image and then "
                "automatically generates the 3D model from it. It appears in the user's 3D Craft app like any "
                "creation made there. Poll GET /api/v1/creations/{creation_id} until stage is done or failed. "
                "Requires models:write."
            ),
            "requestBody": {"required": True, **_json("CreationRequest")},
            "responses": {
                "200": {"description": "Creation accepted", **_json("CreationStatus")},
                "402": {"description": "Not enough Tokens for the whole creation"},
                "409": {"description": "maxTokens is below the current quote, or the idempotencyKey was used for different content"},
            },
        }
    },
    "/api/v1/creations/{creation_id}": {
        "get": {
            "summary": "Poll a one-step creation",
            "parameters": [_id("creation_id")],
            "responses": {"200": {"description": "Stage, progress and download links", **_json("CreationStatus")},
                          "404": {"description": "Not found in this account"}},
        }
    },
    "/api/v1/projects/{project_id}": {
        "get": {
            "summary": "Read one project with its images, conversation, jobs and 3D models",
            "parameters": [_id("project_id")],
            "responses": {"200": {"description": "Project detail", **_json("ProjectDetail")},
                          "404": {"description": "Not found in this account"}},
        },
        "patch": {
            "summary": "Rename a project",
            "parameters": [_id("project_id")],
            "requestBody": {"required": True, "content": {"application/json": {"schema": {
                "type": "object", "required": ["name"],
                "properties": {"name": {"type": "string", "minLength": 1, "maxLength": 120}}}}}},
            "responses": {"200": {"description": "Updated project", **_json("ProjectDetail")}},
        },
        "delete": {
            "summary": "Delete a project and everything in it",
            "description": DELETE_NOTE,
            "parameters": [_id("project_id")],
            "responses": {"200": {"description": "Deleted", **_json("DeleteResult")},
                          "403": {"description": "Key lacks assets:delete"},
                          "409": {"description": "A creation in this project is still running"}},
        },
    },
    "/api/v1/concepts/{concept_id}/image": {
        "get": {
            "summary": "Download a concept image (JPEG)",
            "parameters": [_id("concept_id")],
            "responses": {"200": {"description": "JPEG image", "content": {"image/jpeg": {"schema": {"type": "string", "format": "binary"}}}},
                          "404": {"description": "Not found in this account"}},
        }
    },
    "/api/v1/concepts/{concept_id}": {
        "delete": {
            "summary": "Delete one concept image",
            "description": DELETE_NOTE + " A 3D model made from the image keeps working.",
            "parameters": [_id("concept_id")],
            "responses": {"200": {"description": "Deleted", **_json("DeleteResult")}},
        }
    },
    "/api/v1/assets/{asset_id}": {
        "get": {
            "summary": "Read one owned 3D object, video, or concept image",
            "parameters": [_id("asset_id")],
            "responses": {"200": {"description": "Asset details", **_json("AssetItem")},
                          "404": {"description": "Asset not found in this account"}},
        },
        "patch": {
            "summary": "Rename a 3D object, video, or concept image",
            "description": "Updates the name shown in the owner's library. Requires models:write.",
            "parameters": [_id("asset_id")],
            "requestBody": {"required": True, "content": {"application/json": {"schema": {
                "type": "object", "required": ["name"],
                "properties": {"name": {"type": "string", "minLength": 1, "maxLength": 120}}}}}},
            "responses": {"200": {"description": "Updated asset name"},
                          "404": {"description": "Asset not found in this account"}},
        },
        "delete": {
            "summary": "Delete one 3D object, animation, or concept image",
            "description": DELETE_NOTE + " Deleting a 3D object or video keeps its source concept image; deleting a concept removes its image when no other creation uses it.",
            "parameters": [_id("asset_id")],
            "responses": {"200": {"description": "Deleted", **_json("DeleteResult")}},
        }
    },
}

EXTENDED_SCHEMAS: Dict[str, Any] = {
    "DirectAnimationRequest": {
        "type": "object",
        "required": ["idempotencyKey"],
        "properties": {
            "idempotencyKey": {"type": "string", "minLength": 8, "maxLength": 120, "description": "Unique client token to prevent duplicate charges."},
            "conceptId": {"type": "string", "description": "ID of an existing concept image to animate."},
            "assetId": {"type": "string", "description": "ID of an existing creation asset."},
            "prompt": {"type": "string", "maxLength": 4000, "description": "Text prompt to generate a character and animate it in one step."},
            "motion": {"type": "string", "maxLength": 600, "description": "Specific character actions and turnaround motions."},
            "model": {"type": "string", "enum": ANIMATION_MODELS, "default": "seedance-2.5"},
            "resolution": {"type": "string", "enum": ANIMATION_RESOLUTIONS, "default": "480p"},
            "duration": {"type": "string", "enum": ["4", "5", "6"], "default": "4"},
            "aspect": {"type": "string", "enum": ["1:1", "16:9", "9:16"], "default": "1:1"},
            "maxTokens": {"type": "integer", "minimum": 1, "maximum": 1000, "default": 200},
        },
    },
    "DirectImageRequest": {
        "type": "object",
        "required": ["idempotencyKey", "prompt"],
        "properties": {
            "idempotencyKey": {"type": "string", "minLength": 8, "maxLength": 120},
            "prompt": {"type": "string", "minLength": 1, "maxLength": 4000, "description": "Concept description."},
            "projectId": {"type": "string", "description": "Optional project to bind image to."},
            "style": {"type": "string", "default": "Stylized"},
            "count": {"type": "integer", "minimum": 1, "maximum": 4, "default": 1},
            "maxTokens": {"type": "integer", "minimum": 1, "maximum": 500, "default": 50},
        },
    },
    "ProfileResponse": {
        "type": "object",
        "properties": {
            "uid": {"type": "string"},
            "displayName": {"type": "string"},
            "bio": {"type": "string"},
            "avatarUrl": {"type": "string", "nullable": True},
            "avatarAssetId": {"type": "string", "nullable": True},
            "appearance": {"type": "object"},
            "wallet": {"type": "object"},
            "stats": {"type": "object"},
            "updatedAt": {"type": "number", "nullable": True},
        },
    },
    "ProfileUpdateRequest": {
        "type": "object",
        "properties": {
            "displayName": {"type": "string", "minLength": 1, "maxLength": 64},
            "bio": {"type": "string", "maxLength": 500},
            "avatarUrl": {"type": "string", "maxLength": 1000},
            "avatarAssetId": {"type": "string", "maxLength": 100},
            "appearance": {"type": "object"},
        },
    },
    "FavoriteActionResult": {
        "type": "object",
        "properties": {
            "id": {"type": "string"},
            "favorite": {"type": "boolean"},
        },
    },
    "FavoritesResponse": {
        "type": "object",
        "properties": {
            "favorites": {"type": "array", "items": {"type": "object"}},
        },
    },
    "PromptEnhanceRequest": {
        "type": "object",
        "required": ["prompt"],
        "properties": {
            "prompt": {"type": "string", "minLength": 1, "maxLength": 4000},
            "target": {"type": "string", "enum": ["3d", "animation", "concept"], "default": "3d"},
            "style": {"type": "string", "default": "Stylized"},
        },
    },
    "PromptEnhanceResponse": {
        "type": "object",
        "properties": {
            "originalPrompt": {"type": "string"},
            "target": {"type": "string"},
            "enhancedPrompt": {"type": "string"},
            "negativePrompt": {"type": "string"},
            "suggestedEngine": {"type": "string"},
            "suggestedStyle": {"type": "string"},
        },
    },
}

EXTENDED_PATHS: Dict[str, Any] = {
    "/api/v1/models": {
        "get": {
            "summary": "List selectable 3D and video models",
            "description": "Returns exact model IDs, providers, configured availability, supported video resolutions, and quote links. Availability reflects server configuration, not a provider's live queue status.",
            "responses": {"200": {"description": "Selectable imageTo3D and video models"}},
        },
    },
    "/api/v1/pricing": {
        "get": {
            "summary": "Compare supported 3D and animation model prices",
            "description": "Lists verified provider rates and model identifiers. Generation charges depend on the selected settings; use the creation or animation quote endpoint for a Token spending cap.",
            "responses": {"200": {"description": "Provider price catalogue"}},
        },
    },
    "/api/v1/archive": {
        "get": {
            "summary": "List archived creations",
            "responses": {"200": {"description": "Archived 3D objects, videos, and concept images"}},
        },
    },
    "/api/v1/assets/{asset_id}/archive": {
        "post": {
            "summary": "Archive a 3D object, video, or concept image",
            "description": "Hide an asset from the active library for up to 30 days. Requires assets:delete.",
            "parameters": [_id("asset_id")],
            "responses": {"200": {"description": "Asset archived"}},
        },
    },
    "/api/v1/assets/{asset_id}/restore": {
        "post": {
            "summary": "Restore an archived creation",
            "description": "Move an archived 3D object, video, or concept image back to the active library. Requires models:write.",
            "parameters": [_id("asset_id")],
            "responses": {"200": {"description": "Asset restored"}},
        },
    },
    "/api/v1/animations": {
        "post": {
            "summary": "Create an animated character video loop in one step",
            "description": "Generate an animation from a prompt, concept image, or existing asset. Poll GET /api/v1/animations/{job_id}.",
            "requestBody": {"required": True, **_json("DirectAnimationRequest")},
            "responses": {
                "200": {"description": "Animation job created"},
                "402": {"description": "Not enough Tokens"},
                "409": {"description": "maxTokens below quote or idempotency conflict"},
            },
        },
    },
    "/api/v1/animations/{job_id}": {
        "get": {
            "summary": "Poll character animation status",
            "parameters": [_id("job_id")],
            "responses": {
                "200": {"description": "Animation status, progress and download link"},
                "404": {"description": "Animation not found"},
            },
        },
    },
    "/api/v1/animations/{job_id}/download": {
        "get": {
            "summary": "Download rendered MP4 character animation",
            "parameters": [_id("job_id")],
            "responses": {
                "200": {"description": "MP4 video stream", "content": {"video/mp4": {"schema": {"type": "string", "format": "binary"}}}},
                "404": {"description": "Animation file not found"},
            },
        },
    },
    "/api/v1/images": {
        "post": {
            "summary": "Generate a concept image in one step",
            "requestBody": {"required": True, **_json("DirectImageRequest")},
            "responses": {
                "200": {"description": "Image generation job created"},
                "402": {"description": "Not enough Tokens"},
            },
        },
    },
    "/api/v1/images/{concept_id}": {
        "get": {
            "summary": "Get concept image metadata",
            "parameters": [_id("concept_id")],
            "responses": {
                "200": {"description": "Concept image details"},
                "404": {"description": "Image not found"},
            },
        },
    },
    "/api/v1/images/{concept_id}/download": {
        "get": {
            "summary": "Download concept image binary (JPEG)",
            "parameters": [_id("concept_id")],
            "responses": {
                "200": {"description": "JPEG binary stream", "content": {"image/jpeg": {"schema": {"type": "string", "format": "binary"}}}},
                "404": {"description": "Image not found"},
            },
        },
    },
    "/api/v1/profile": {
        "get": {
            "summary": "Get creator profile, wallet balance, and creation statistics",
            "responses": {
                "200": {"description": "Creator profile", **_json("ProfileResponse")},
            },
        },
        "patch": {
            "summary": "Update creator profile (displayName, bio, avatarUrl, appearance)",
            "requestBody": {"required": True, **_json("ProfileUpdateRequest")},
            "responses": {
                "200": {"description": "Updated profile", **_json("ProfileResponse")},
            },
        },
    },
    "/api/v1/favorites": {
        "get": {
            "summary": "List all favorited creations and assets",
            "responses": {
                "200": {"description": "Favorited assets", **_json("FavoritesResponse")},
            },
        },
    },
    "/api/v1/assets/{asset_id}/favorite": {
        "post": {
            "summary": "Add asset to favorites",
            "parameters": [_id("asset_id")],
            "responses": {
                "200": {"description": "Asset marked as favorite", **_json("FavoriteActionResult")},
                "404": {"description": "Asset not found"},
            },
        },
        "delete": {
            "summary": "Remove asset from favorites",
            "parameters": [_id("asset_id")],
            "responses": {
                "200": {"description": "Asset removed from favorites", **_json("FavoriteActionResult")},
                "404": {"description": "Asset not found"},
            },
        },
    },
    "/api/v1/prompts/enhance": {
        "post": {
            "summary": "Enhance and optimize prompts for 3D reconstruction and character animation using Gemini 3.8 Flash",
            "requestBody": {"required": True, **_json("PromptEnhanceRequest")},
            "responses": {
                "200": {"description": "Optimized prompt recommendations", **_json("PromptEnhanceResponse")},
            },
        },
    },
    "/api/v1/community/games": {
        "get": {
            "summary": "Explore community games and interactive worlds",
            "parameters": [
                {"name": "category", "in": "query", "required": False, "schema": {"type": "string", "enum": ["fun", "gameplay", "visual", "audio", "creative", "new"], "default": "fun"}},
                {"name": "offset", "in": "query", "required": False, "schema": {"type": "integer", "default": 0}},
            ],
            "responses": {
                "200": {"description": "Community games feed"},
            },
        },
    },
}
