use axum::{Json, Router, routing::get};
use serde::Serialize;
use std::net::SocketAddr;

#[derive(Serialize)]
struct RuntimeStatus {
    mode: &'static str,
    identity: &'static str,
    messaging: &'static str,
    calls: &'static str,
    peer_connections: u32,
}

async fn status() -> Json<RuntimeStatus> {
    Json(RuntimeStatus {
        mode: "local_scaffold",
        identity: "not_implemented",
        messaging: "not_implemented",
        calls: "not_implemented",
        peer_connections: 0,
    })
}

async fn health() -> &'static str {
    "ok"
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let app = Router::new()
        .route("/health", get(health))
        .route("/api/status", get(status));
    let address = SocketAddr::from(([127, 0, 0, 1], 3707));
    let listener = tokio::net::TcpListener::bind(address).await?;
    println!("Slouching peer scaffold listening on http://{address}");
    axum::serve(listener, app).await?;
    Ok(())
}
