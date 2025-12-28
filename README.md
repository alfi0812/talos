<div align="center">

# 🧊 Personal Talos Kubernetes Cluster

*A self-hosted, GitOps-driven Kubernetes cluster built on Talos Linux, focused on reliability, observability, and clean automation.*

[![Truenas](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.alfi0812.de%2Ftruenas_version&style=for-the-badge&logo=truenas&logoColor=white&label=%20&color=blue)](https://www.truenas.com/)&nbsp;&nbsp;
[![Talos](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.alfi0812.de%2Ftalos_version&style=for-the-badge&logo=talos&logoColor=white&label=%20&color=blue)](https://www.talos.dev/)&nbsp;&nbsp;
[![Kubernetes](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.alfi0812.de%2Fkubernetes_version&style=for-the-badge&logo=kubernetes&logoColor=white&label=%20&color=blue)](https://www.kubernetes.io/)&nbsp;&nbsp;
[![Flux](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.alfi0812.de%2Fflux_version&style=for-the-badge&logo=flux&logoColor=white&color=blue&label=%20)](https://fluxcd.io)&nbsp;&nbsp;

[![Home-Internet](https://img.shields.io/endpoint?url=https%3A%2F%2Fstatus.boemeltrein.nl%2Fapi%2Fv1%2Fendpoints%2Fbuddy_ping-(buddy)%2Fhealth%2Fbadge.shields&style=for-the-badge&logo=ubiquiti&logoColor=white&label=Home%20Internet)](https://status.goeppel.dev)&nbsp;&nbsp;
[![Status-Page](https://img.shields.io/endpoint?url=https%3A%2F%2Fstatus.boemeltrein.nl%2Fapi%2Fv1%2Fendpoints%2Fbuddy_status-page-(buddy)%2Fhealth%2Fbadge.shields&style=for-the-badge&logo=statuspage&logoColor=white&label=Status%20Page)](https://status.goeppel.dev)&nbsp;&nbsp;
[![Alertmanager](https://img.shields.io/endpoint?url=https%3A%2F%2Fstatus.boemeltrein.nl%2Fapi%2Fv1%2Fendpoints%2Fbuddy_heartbeat-(buddy)%2Fhealth%2Fbadge.shields&style=for-the-badge&logo=prometheus&logoColor=white&label=Alertmanager)](https://status.goeppel.dev)

[![Age-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.alfi0812.de%2Fcluster_age_days&style=flat-square&label=Age)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Uptime-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.alfi0812.de%2Fcluster_uptime_days&style=flat-square&label=Uptime)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Node-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.alfi0812.de%2Fcluster_node_count&style=flat-square&label=Nodes)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Pod-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.alfi0812.de%2Fcluster_pod_count&style=flat-square&label=Pods)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![CPU-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.alfi0812.de%2Fcluster_cpu_usage&style=flat-square&label=CPU)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Memory-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.alfi0812.de%2Fcluster_memory_usage&style=flat-square&label=Memory)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Alerts](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.alfi0812.de%2Fcluster_alert_count&style=flat-square&label=Alerts)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;

</div>

---

## 📌 Overview

This repository contains the full **GitOps-managed configuration** for my personal Kubernetes cluster.
The cluster runs on **Talos Linux** and is fully declarative: every component, application, and configuration is defined in Git and continuously reconciled using **FluxCD**.

Key goals of this setup:

* 🔁 **Reproducibility** – rebuild the entire cluster from Git
* 🔒 **Immutability & Security** – minimal OS, no SSH, API-driven management
* 📈 **Observability** – metrics, alerts, and public status visibility
* 🤖 **Automation-first** – updates, deployments, and testing without manual intervention

---

## 🧠 Design Decisions

### Why Talos Linux?
- Immutable, minimal OS reduces attack surface
- No SSH or package manager
- Fully API-driven, ideal for GitOps-based Kubernetes clusters

### Why FluxCD?
- Continuous reconciliation instead of one-shot deployments
- Native Kubernetes integration
- Works seamlessly with SOPS for encrypted secrets

---

## 🧩 Core Components

| Component          | Description                                                                     |
| ------------------ | ------------------------------------------------------------------------------- |
| **Kubernetes**     | Container orchestration platform for running and managing workloads             |
| **Talos Linux**    | Immutable, API-driven Linux distribution purpose-built for Kubernetes           |
| **FluxCD**         | GitOps operator used for continuous reconciliation of cluster state             |
| **Mend Renovate**  | Automatically tracks and updates container images and dependencies              |
| **GitHub Actions** | CI pipelines for validation, linting, and testing of cluster configs            |
| **SOPS**           | Encryption of all secrets and credentials stored in Git, integrated with FluxCD |

---

## 🗂 Directory Structure

```text
clusters/
└── main/
    ├── components/   # Common components applied to multiple parts of the cluster
    ├── kubernetes/   # Applications and Kubernetes workloads
    └── talos/        # Talos Linux machine and cluster configuration
```

---

## 🔐 Secrets Management

All secrets and credentials are stored in this repository **encrypted with SOPS**.

- Secrets are committed to Git in encrypted form
- Decryption happens inside the cluster via FluxCD
- Decryption keys are managed externally and are never stored in Git
- This enables full GitOps workflows without exposing sensitive data

---

## ☁️ Cloud & External Dependencies

| Service        | Usage                                                     |
| -------------- | --------------------------------------------------------- |
| **Cloudflare** | DNS management, tunnels, and S3-compatible object storage |
| **GitHub**     | Source control, CI, and GitOps reconciliation source      |

---

## 🖥 Hardware

### TrueNAS Storage Server

| Component             | Specification                    |
| --------------------- | -------------------------------- |
| **CPU**               | AMD Ryzen 7 5700G                |
| **RAM**               | 64 GB DDR4 @ 3200 MHz            |
| **SAS Controller**    | LSI SAS 9300-16i                 |
| **Boot Drive**        | 1× Crucial P310 500 GB NVMe      |
| **Metadata VDEV**     | 2× Samsung 870 EVO 1 TB (Mirror) |
| **Data VDEV**         | 6× Seagate Exos X24 16 TB HDD    |
| **Remote Management** | NanoKVM PCIe Edition             |

### Talos Kubernetes Node

| Component             | Specification                  |
| --------------------- | ------------------------------ |
| **CPU**               | AMD Ryzen 9 9950X              |
| **RAM**               | 128 GB DDR5 @ 5600 MHz         |
| **Storage**           | 2 TB Crucial P3 Plus NVMe      |
| **GPU**               | Sparkle Intel Arc A770 (16 GB) |
| **Remote Management** | NanoKVM PCIe Edition           |

---

## 📊 Monitoring & Status

* 📈 **Metrics & Dashboards** via Prometheus-compatible tooling
* 🚨 **Alerting** with Alertmanager
* 🌍 **Public Status Page** for service and connectivity visibility
* 🧮 **Cluster Statistics** exposed via Kromgo and Shields.io

---

## 🙏 Acknowledgements

This cluster is heavily inspired by and built upon the excellent work of:

* **TrueCharts** – [https://trueforge.org/](https://trueforge.org/)
* **Home Operations** – [https://github.com/home-operations](https://github.com/home-operations)

Their open-source contributions and documentation made this setup possible.

---

> ⚠️ **Note**
> This repository is public for transparency and learning purposes. Secrets and credentials **are stored in Git in encrypted form** using **SOPS**.
> Decryption keys are managed externally and are **not** committed to the repository, ensuring sensitive values remain protected.

> 🧪 This cluster is used as a learning, testing, and long-running homelab environment.  
> Configurations may evolve as new Kubernetes, Talos, or GitOps features are evaluated.
