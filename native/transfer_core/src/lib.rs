//! Shared networking primitives for Transfer.
//!
//! The Flutter bridge will be added after this crate's API is stable. Keeping
//! mDNS behind this small Rust API prevents platform and UI code from
//! depending directly on discovery implementation details.

mod frb_generated;

use std::net::IpAddr;

use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};

pub mod api;

pub const SERVICE_TYPE: &str = "_transfer._tcp.local.";
pub const PROTOCOL_VERSION: &str = "1";
/// Fixed local-control port so users can allow one port in the desktop firewall.
pub const PAIRING_PORT: u16 = 39871;

pub struct DiscoveryDaemon {
    daemon: ServiceDaemon,
}

impl DiscoveryDaemon {
    pub fn new() -> Result<Self, mdns_sd::Error> {
        Ok(Self {
            daemon: ServiceDaemon::new()?,
        })
    }

    pub fn browse(&self) -> Result<mdns_sd::Receiver<ServiceEvent>, mdns_sd::Error> {
        self.daemon.browse(SERVICE_TYPE)
    }

    pub fn register(
        &self,
        instance_name: &str,
        device_id: &str,
        port: u16,
    ) -> Result<(), mdns_sd::Error> {
        validate_label(instance_name).map_err(mdns_sd::Error::Msg)?;
        validate_label(device_id).map_err(mdns_sd::Error::Msg)?;

        let host_name = format!("{}.local.", device_id);
        let properties = [("id", device_id), ("v", PROTOCOL_VERSION)];
        let service = ServiceInfo::new(
            SERVICE_TYPE,
            instance_name,
            &host_name,
            &[] as &[IpAddr],
            port,
            &properties[..],
        )?;

        self.daemon.register(service).map(|_| ())
    }

    pub fn shutdown(self) -> Result<(), mdns_sd::Error> {
        self.daemon.shutdown().map(|_| ())
    }
}

fn validate_label(value: &str) -> Result<(), String> {
    if value.is_empty() || value.len() > 15 {
        return Err("mDNS label must contain 1 to 15 characters".to_owned());
    }

    if !value
        .chars()
        .all(|character| character.is_ascii_alphanumeric() || character == '-')
    {
        return Err("mDNS label contains an invalid character".to_owned());
    }

    if value.starts_with('-') || value.ends_with('-') || value.contains("--") {
        return Err("mDNS label has an invalid hyphen placement".to_owned());
    }

    if !value
        .chars()
        .any(|character| character.is_ascii_alphabetic())
    {
        return Err("mDNS label must contain at least one letter".to_owned());
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::validate_label;

    #[test]
    fn accepts_safe_labels() {
        assert!(validate_label("transfer-phone").is_ok());
    }

    #[test]
    fn rejects_unsafe_labels() {
        assert!(validate_label("../device").is_err());
        assert!(validate_label("123456").is_err());
        assert!(validate_label("-device").is_err());
    }
}
