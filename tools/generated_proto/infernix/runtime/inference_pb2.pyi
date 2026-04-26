from __future__ import annotations

from google.protobuf.message import Message


class WorkerRequest(Message):
    request_model_id: str
    input_text: str
    runtime_mode: str
    selected_engine: str
    adapter_id: str

    def __init__(
        self,
        *,
        request_model_id: str = ...,
        input_text: str = ...,
        runtime_mode: str = ...,
        selected_engine: str = ...,
        adapter_id: str = ...,
    ) -> None: ...

    def ParseFromString(self, serialized: bytes) -> int: ...
    def SerializeToString(self) -> bytes: ...


class WorkerResponse(Message):
    output_text: str
    error_code: str
    error_message: str

    def __init__(
        self,
        *,
        output_text: str = ...,
        error_code: str = ...,
        error_message: str = ...,
    ) -> None: ...

    def ParseFromString(self, serialized: bytes) -> int: ...
    def SerializeToString(self) -> bytes: ...
