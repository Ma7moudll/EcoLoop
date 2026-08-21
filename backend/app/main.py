from __future__ import annotations

import asyncio
import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import settings
from .database import SessionLocal, create_tables
from .mqtt import MqttGateway, handler
from .routers import (
    admin_router,
    ai_router,
    auth_router,
    debug_router,
    deposit_router,
    stations_router,
    user_data_router,
    ws_router,
)
from .services import LeaderboardService, event_bus, registry, seed
from .state import configure_gateway

logging.basicConfig(
    level=logging.DEBUG if settings.debug else logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("recycle.main")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Production secret guard: refuse to boot with development defaults.
    # Raises before any listener accepts traffic.
    settings.validate_production()

    # Database: migrations own the schema in production; `create_tables` is a
    # convenience for dev/test when Alembic has not been run yet.
    create_tables()

    db = SessionLocal()
    try:
        if settings.seed_on_startup:
            seed(db, seed_demo_user=settings.seed_demo_user)
            LeaderboardService().repair(db)
    finally:
        db.close()

    # Seed the station registry with the DB stations so the UI has a wiring.
    from .models import Station
    from .services.station_registry import StationSnapshot

    db = SessionLocal()
    try:
        for station in db.query(Station).all():
            if registry.get(station.station_code) is None:
                registry.register(
                    StationSnapshot(
                        station_id=station.station_code,
                        code=station.station_code,
                        name=station.name,
                        status=station.status,
                    )
                )
    finally:
        db.close()

    gateway = MqttGateway()
    configure_gateway(gateway)
    handler.install_handlers(gateway)
    gateway.start()
    event_bus.attach_loop(asyncio.get_event_loop())

    logger.info("[MQTT] starting gateway %s:%s tls=%s", gateway.broker_host, gateway.broker_port, settings.mqtt_tls)

    yield

    gateway.stop()
    configure_gateway(None)


def create_app() -> FastAPI:
    app = FastAPI(title=settings.app_name, version="1.0.0", lifespan=lifespan)
    origins = settings.allowed_origin_list()
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type", "X-Station-Key"],
    )

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
        """Catch-all for unexpected errors.

        Full stack trace goes to SERVER logs only; the client receives a
        generic body with no internals (no paths, no SQL, no secrets)."""
        logger.exception(
            "[ERROR] unhandled exception on %s %s", request.method, request.url.path
        )
        return JSONResponse(status_code=500, content={"error": "internal_server_error"})

    prefix = settings.api_v1_prefix
    app.include_router(auth_router, prefix=prefix)
    app.include_router(ai_router, prefix=prefix)
    app.include_router(deposit_router, prefix=prefix)
    app.include_router(stations_router, prefix=prefix)
    app.include_router(user_data_router, prefix=prefix)
    app.include_router(admin_router, prefix=prefix)
    app.include_router(ws_router)

    # Debug-only byte-identity fingerprint route. Mounted ONLY when explicitly
    # enabled (`DEBUG_IMAGE_HASH=true`) so it never exists for normal users.
    if settings.debug_image_hash:
        app.include_router(debug_router, prefix=prefix)

    @app.get("/health")
    def health() -> dict:
        """Real dependency health: database, MQTT gateway, AI service.

        `status` is `ok` only when every dependency answers; otherwise
        `degraded`. Responses never include connection strings or hosts."""
        components: dict[str, str] = {}
        components["db"] = _check_db()
        components["mqtt"] = _check_mqtt()
        components["ai"] = _check_ai()
        status = "ok" if all(v == "ok" for v in components.values()) else "degraded"
        return {"status": status, "app": settings.app_name, **components}

    return app


def _check_db() -> str:
    from sqlalchemy import text

    try:
        db = SessionLocal()
        try:
            db.execute(text("SELECT 1"))
        finally:
            db.close()
        return "ok"
    except Exception:
        logger.warning("[HEALTH] database unreachable")
        return "unreachable"


def _check_mqtt() -> str:
    from .state import get_gateway

    gateway = get_gateway()
    if gateway is None or not gateway.connected.is_set():
        logger.warning("[HEALTH] mqtt gateway not connected")
        return "unreachable"
    return "ok"


def _check_ai() -> str:
    import httpx

    try:
        res = httpx.get(
            f"{settings.ai_service_url.rstrip('/')}/health",
            timeout=min(settings.ai_timeout_seconds, 3.0),
        )
        return "ok" if res.status_code == 200 else "degraded"
    except Exception:
        logger.warning("[HEALTH] ai service unreachable")
        return "unreachable"


app = create_app()
