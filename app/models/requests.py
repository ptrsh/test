from typing import List
from pydantic import BaseModel


class AppInfo(BaseModel):
    app_type: str
    package_name: str


class StoreInfo(BaseModel):
    type: str
    apps: List[AppInfo]


class ReviewsRequest(BaseModel):
    stores: List[StoreInfo]