from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from ..database import Base


class Station(Base):
    """One physical EcoLoop unit (single body, four internal compartments).

    Compartments are positions 1..4 defined by routing_policy, not separate
    station entities.
    """

    __tablename__ = "stations"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    station_code: Mapped[str] = mapped_column(String(32), unique=True, nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="offline")
    # Bin state surfaced to admins: a full bin and/or an error condition that
    # the station reports over MQTT. Drives the admin alert banner.
    bin_full: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    last_error: Mapped[str | None] = mapped_column(String(255), nullable=True)
    # Which mechanical implementation the unit runs. Domain-level metadata
    # only — commands express compartment intent (`destination_position`),
    # never mechanics. EcoLoop stations run the Rotary V2 chute.
    mechanism: Mapped[str] = mapped_column(String(16), nullable=False, default="rotary")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )