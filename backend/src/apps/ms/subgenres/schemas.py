# Built-in Dependencies
from datetime import datetime

# Third-Party Dependencies
from pydantic import ConfigDict

# Local Dependencies
from src.apps.ms.subgenres.models import SubgenreContentBase
from src.core.common.models import UUIDMixin, TimestampMixin, SoftDeleteMixin
from src.core.utils.partial import optional


class SubgenreBase(SubgenreContentBase):
    pass


class Subgenre(
    SubgenreBase,
    UUIDMixin,
    TimestampMixin,
    SoftDeleteMixin,
):
    pass


class SubgenreRead(SubgenreBase, UUIDMixin, TimestampMixin):
    pass


class SubgenreCreate(
    SubgenreBase,
):
    model_config = ConfigDict(extra="forbid")


class SubgenreCreateInternal(SubgenreCreate):
    pass


@optional()
class SubgenreUpdate(
    SubgenreContentBase,
):
    model_config = ConfigDict(extra="forbid")


class SubgenreUpdateInternal(SubgenreUpdate):
    updated_at: datetime


class SubgenreDeleteInternal(SoftDeleteMixin):
    model_config = ConfigDict(extra="forbid")
