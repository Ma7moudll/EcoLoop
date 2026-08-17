from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .database import SessionLocal, create_tables
from .mqtt import MqttGateway, handler
from .routers import (
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
    # Database: migrations own the schema in production; `create_tables` is a
    # convenience for dev/test when Alembic has not been run yet.
    create_tables()

    db = SessionLocal()
    try:
        if settings.seed_on_startup:
            seed(db)
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

    logger.info("[MQTT] starting gateway %s:%s", gateway.broker_host, gateway.broker_port)

    yield

    gateway.stop()
    configure_gateway(None)


def create_app() -> FastAPI:
    app = FastAPI(title=settings.app_name, version="1.0.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    prefix = settings.api_v1_prefix
    app.include_router(auth_router, prefix=prefix)
    app.include_router(ai_router, prefix=prefix)
    app.include_router(deposit_router, prefix=prefix)
    app.include_router(stations_router, prefix=prefix)
    app.include_router(user_data_router, prefix=prefix)
    app.include_router(ws_router)

    # Debug-only byte-identity fingerprint route. Mounted ONLY when explicitly
    # enabled (`DEBUG_IMAGE_HASH=true`) so it never exists for normal users.
    if settings.debug_image_hash:
        app.include_router(debug_router, prefix=prefix)

    @app.get("/health")
    def health() -> dict:
        return {"status": "ok", "app": settings.app_name}

    return app


app = create_app()