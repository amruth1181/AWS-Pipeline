# UrbanMove — Real-Time Paris Mobility Platform on AWS

> 🚧 Work in progress. Claude Code rewrites this README fully in Phase 11 (see `docs/IMPLEMENTATION.md`).

A cloud-native platform that streams **live Vélib' bike-share data** and **Paris road-traffic sensors** through
AWS (Kinesis → Lambda → DynamoDB / S3 + Athena), and serves availability, congestion insights and trip
recommendations through a **Cognito-secured API on ECS Fargate** and a live web map. Everything is in Terraform,
deployed by GitHub Actions with OIDC, monitored in CloudWatch, and designed for high availability, DR and low cost.

**Stack:** AWS (Kinesis, Firehose, Lambda, DynamoDB, S3, Glue, Athena, ECS Fargate, ALB, API Gateway, Cognito,
CloudFront, CloudWatch, X-Ray, Budgets, Backup) · Terraform · Python 3.12 · FastAPI · Docker · GitHub Actions · Leaflet

## Status

See [`docs/PROGRESS.md`](docs/PROGRESS.md).

## Docs

- [Project brief](docs/PROJECT_BRIEF.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Build plan](docs/IMPLEMENTATION.md)
- [Data sources](docs/DATA_SOURCES.md)
- [Decisions (ADRs)](docs/DECISIONS.md)

## Data attribution

- Vélib' Métropole open data (GBFS), Licence Ouverte / Open Licence
- Ville de Paris, comptages routiers permanents, ODbL
- Map tiles © OpenStreetMap contributors

## Author

Amruth Ganta, MSc AI Systems & Data Science, EPITA Paris
