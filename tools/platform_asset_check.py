#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
REQUIRED_FILES = [
    Path("chart/Chart.yaml"),
    Path("chart/values.yaml"),
    Path("chart/templates/configmap-demo-catalog.yaml"),
    Path("chart/templates/configmap-publication-state.yaml"),
    Path("chart/templates/deployment-edge.yaml"),
    Path("chart/templates/deployment-service.yaml"),
    Path("chart/templates/deployment-web.yaml"),
    Path("chart/templates/edge-configmap.yaml"),
    Path("chart/templates/persistentvolumeclaim-service-data.yaml"),
    Path("chart/templates/runtimeclass-nvidia.yaml"),
    Path("chart/templates/service-api.yaml"),
    Path("chart/templates/service-edge.yaml"),
    Path("chart/templates/service-web.yaml"),
    Path("chart/templates/workloads-platform-portals.yaml"),
    Path("kind/cluster-apple-silicon.yaml"),
    Path("kind/cluster-linux-cpu.yaml"),
    Path("kind/cluster-linux-cuda.yaml"),
]
REQUIRED_PHRASES = {
    Path("chart/values.yaml"): ["runtimeMode:", "upstreamCharts:", "harbor:", "minio:", "pulsar:", "platformPortals:", "catalogPayload:", "publication:", "engineAdapters:", "commandEnv:", "30002", "30011", "30080", "30650", "/api", "/harbor", "/minio/console", "/pulsar/admin", "storageClass: infernix-manual", "storageClassName: infernix-manual"],
    Path("chart/templates/deployment-service.yaml"): ["demoConfig.mountPath", "INFERNIX_DEMO_CONFIG_PATH", "INFERNIX_PUBLICATION_STATE_PATH", "INFERNIX_ROUTE_PROBE_BASE_URL", "INFERNIX_MINIO_ENDPOINT", "INFERNIX_PULSAR_ADMIN_URL", "INFERNIX_PULSAR_WS_BASE_URL", ".Values.service.engineAdapters.commandEnv", "runtimeClassName: nvidia", "infernix.runtime/gpu", "nvidia.com/gpu"],
    Path("chart/templates/deployment-web.yaml"): ["demoConfig.mountPath", "demoConfig.name"],
    Path("chart/templates/edge-configmap.yaml"): ["edge-port", "routes.yaml", ".Values.edge.routes"],
    Path("chart/templates/deployment-edge.yaml"): ["command:", "- infernix", "args:", "- edge", "INFERNIX_SERVICE_UPSTREAM", "INFERNIX_WEB_UPSTREAM", "INFERNIX_HARBOR_UPSTREAM", "INFERNIX_MINIO_UPSTREAM", "INFERNIX_PULSAR_UPSTREAM"],
    Path("chart/templates/persistentvolumeclaim-service-data.yaml"): ["storageClassName:", "infernix.io/workload: service", ".Values.service.dataPvc.name"],
    Path("chart/templates/runtimeclass-nvidia.yaml"): ["RuntimeClass", "name: nvidia", "handler: nvidia", ".Values.runtimeMode", "linux-cuda"],
    Path("chart/templates/workloads-platform-portals.yaml"): ["infernix-harbor-gateway", "infernix-minio-gateway", "infernix-pulsar-gateway", "- gateway", "- harbor", "- minio", "- pulsar", "INFERNIX_HARBOR_BACKEND_URL", "INFERNIX_MINIO_S3_ENDPOINT", "INFERNIX_PULSAR_ADMIN_URL"],
    Path("chart/templates/service-edge.yaml"): ["type: NodePort", "nodePort:"],
    Path("kind/cluster-linux-cuda.yaml"): ["/var/run/nvidia-container-devices/all", "kindest/node:v1.34.0", "infernix.runtime/gpu=true", "/etc/containerd/certs.d", "./.build/kind/registry", "apiServerAddress: \"127.0.0.1\"", "listenAddress: \"127.0.0.1\"", "containerPort: 30080", "containerPort: 30650"],
    Path("kind/cluster-apple-silicon.yaml"): ["kindest/node:v1.34.0", "/etc/containerd/certs.d", "./.build/kind/registry", "apiServerAddress: \"127.0.0.1\"", "listenAddress: \"127.0.0.1\"", "containerPort: 30011", "containerPort: 30080", "containerPort: 30650"],
    Path("kind/cluster-linux-cpu.yaml"): ["kindest/node:v1.34.0", "/etc/containerd/certs.d", "./.build/kind/registry", "apiServerAddress: \"127.0.0.1\"", "listenAddress: \"127.0.0.1\"", "containerPort: 30011", "containerPort: 30080", "containerPort: 30650"],
}


def fail(message: str) -> None:
    print(f"platform-asset-check: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    for relative_path in REQUIRED_FILES:
        full_path = REPO_ROOT / relative_path
        if not full_path.exists():
            fail(f"missing required platform asset: {relative_path}")

    for relative_path, phrases in REQUIRED_PHRASES.items():
        contents = (REPO_ROOT / relative_path).read_text(encoding="utf-8")
        for phrase in phrases:
            if phrase not in contents:
                fail(f"{relative_path} is missing required phrase: {phrase}")

    print("platform-asset-check: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
