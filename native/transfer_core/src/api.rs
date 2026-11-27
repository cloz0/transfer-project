use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::net::{Ipv4Addr, TcpListener, TcpStream};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use serde::{Deserialize, Serialize};
use snow::{Builder, HandshakeState};

const MAX_FRAME_SIZE: usize = 16 * 1024;
const PAIRING_TIMEOUT: Duration = Duration::from_secs(60);
const NOISE_PARAMS: &str = "Noise_XX_25519_ChaChaPoly_BLAKE2s";

#[derive(Debug, Clone)]
pub struct DiscoveredDevice {
    pub name: String,
    pub platform: String,
    pub address: String,
    pub port: u16,
    pub device_id: String,
    pub protocol_version: String,
}

#[derive(Debug, Clone)]
pub struct IncomingPairingRequest {
    pub request_id: String,
    pub device_id: String,
    pub device_name: String,
    pub protocol_version: String,
    pub address: String,
    pub security_code: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct PairingRequestWire {
    kind: String,
    request_id: String,
    device_id: String,
    device_name: String,
    protocol_version: String,
    handshake_message: Vec<u8>,
}

#[derive(Debug, Serialize, Deserialize)]
struct PairingHandshakeWire {
    kind: String,
    handshake_message: Vec<u8>,
}

#[derive(Debug, Serialize, Deserialize)]
struct PairingDecisionWire {
    accepted: bool,
    reason: String,
}

struct PendingPairing {
    stream: TcpStream,
    handshake: HandshakeState,
}

struct LocalService {
    daemon: ServiceDaemon,
    listener: TcpListener,
    pending: BTreeMap<String, PendingPairing>,
}

static LOCAL_SERVICE: OnceLock<Mutex<Option<LocalService>>> = OnceLock::new();

fn local_service_slot() -> &'static Mutex<Option<LocalService>> {
    LOCAL_SERVICE.get_or_init(|| Mutex::new(None))
}

/// Returns the discovery protocol version used by the Rust core.
pub fn protocol_version() -> String {
    crate::PROTOCOL_VERSION.to_owned()
}

/// Opens a local TCP endpoint and advertises this device over mDNS.
///
/// The endpoint is intentionally only a discovery placeholder at this stage;
/// the authenticated transfer listener will replace it in a later step.
pub fn start_local_service(
    instance_name: String,
    device_id: String,
    platform: String,
) -> Result<u16, String> {
    // Release an older listener first. This matters during Flutter hot restart,
    // where the Rust process can survive while Dart starts main() again.
    {
        let mut slot = local_service_slot()
            .lock()
            .map_err(|_| "Yerel servis kilidi kullanılamıyor".to_owned())?;
        if let Some(previous) = slot.take() {
            let _ = previous.daemon.shutdown();
            drop(previous.listener);
        }
    }

    // A stable port makes desktop firewall configuration predictable. The
    // listener still binds to all local interfaces, not to the public internet.
    let listener = TcpListener::bind(("0.0.0.0", crate::PAIRING_PORT)).map_err(|error| {
        format!(
            "Yerel servis portu açılamadı ({}): {error}",
            crate::PAIRING_PORT
        )
    })?;
    listener
        .set_nonblocking(true)
        .map_err(|error| error.to_string())?;
    let port = listener
        .local_addr()
        .map_err(|error| error.to_string())?
        .port();
    let daemon = ServiceDaemon::new().map_err(|error| error.to_string())?;

    let host_name = format!("{}.local.", device_id);
    let properties = [
        ("id", device_id.as_str()),
        ("v", crate::PROTOCOL_VERSION),
        ("platform", platform.as_str()),
    ];
    let service = ServiceInfo::new(
        crate::SERVICE_TYPE,
        &instance_name,
        &host_name,
        &[] as &[std::net::IpAddr],
        port,
        &properties[..],
    )
    .map_err(|error| error.to_string())?
    .enable_addr_auto();
    daemon
        .register(service)
        .map_err(|error| error.to_string())?;

    let mut slot = local_service_slot()
        .lock()
        .map_err(|_| "Yerel servis kilidi kullanılamıyor".to_owned())?;
    *slot = Some(LocalService {
        daemon,
        listener,
        pending: BTreeMap::new(),
    });
    Ok(port)
}

pub fn stop_local_service() -> Result<(), String> {
    let mut slot = local_service_slot()
        .lock()
        .map_err(|_| "Yerel servis kilidi kullanılamıyor".to_owned())?;
    if let Some(service) = slot.take() {
        service
            .daemon
            .shutdown()
            .map_err(|error| error.to_string())?;
        drop(service.listener);
    }
    Ok(())
}

/// Sends a user-visible pairing request to a discovered device.
///
/// This is only the request transport. It does not authorize a device or
/// exchange files; the receiver must still display and approve the request.
pub fn send_pairing_request(
    address: String,
    port: u16,
    device_id: String,
    device_name: String,
) -> Result<String, String> {
    let endpoint = if address.contains(':') {
        format!("[{address}]:{port}")
    } else {
        format!("{address}:{port}")
    };
    let socket = endpoint
        .parse()
        .map_err(|error| format!("Geçersiz cihaz adresi: {error}"))?;
    let mut stream = TcpStream::connect_timeout(&socket, Duration::from_secs(2))
        .map_err(|error| format!("Cihaza bağlanılamadı: {error}"))?;
    stream
        .set_read_timeout(Some(PAIRING_TIMEOUT))
        .and_then(|_| stream.set_write_timeout(Some(Duration::from_secs(2))))
        .map_err(|error| error.to_string())?;

    let params = NOISE_PARAMS
        .parse()
        .map_err(|error| format!("Güvenli protokol başlatılamadı: {error}"))?;
    let builder = Builder::new(params);
    let keypair = builder
        .generate_keypair()
        .map_err(|error| format!("Yerel özel anahtar oluşturulamadı: {error}"))?;
    let mut handshake = builder
        .local_private_key(&keypair.private)
        .map_err(|error| format!("Yerel özel anahtar ayarlanamadı: {error}"))?
        .build_initiator()
        .map_err(|error| format!("Güvenli oturum başlatılamadı: {error}"))?;
    let mut handshake_message = vec![0; 1024];
    let length = handshake
        .write_message(&[], &mut handshake_message)
        .map_err(|error| format!("Güvenli istek oluşturulamadı: {error}"))?;
    handshake_message.truncate(length);

    let request_id = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_nanos()
        .to_string();
    let request = PairingRequestWire {
        kind: "pairing_request".to_owned(),
        request_id,
        device_id,
        device_name,
        protocol_version: crate::PROTOCOL_VERSION.to_owned(),
        handshake_message,
    };
    write_frame(&mut stream, &request)?;

    let response: PairingHandshakeWire = read_frame(&mut stream)?;
    if response.kind != "pairing_handshake" {
        return Err("Geçersiz güvenli oturum cevabı".to_owned());
    }
    let mut payload = [0_u8; 1024];
    handshake
        .read_message(&response.handshake_message, &mut payload)
        .map_err(|error| format!("Güvenli oturum doğrulanamadı: {error}"))?;
    let security_code = security_code(handshake.get_handshake_hash());
    let mut final_message = vec![0; 1024];
    let length = handshake
        .write_message(&[], &mut final_message)
        .map_err(|error| format!("Güvenli oturum tamamlanamadı: {error}"))?;
    final_message.truncate(length);
    write_frame(&mut stream, &final_message)?;

    let mut transport = handshake
        .into_transport_mode()
        .map_err(|error| format!("Şifreli kanala geçilemedi: {error}"))?;
    let encrypted: Vec<u8> = read_frame(&mut stream)?;
    let mut decision_payload = vec![0; MAX_FRAME_SIZE];
    let length = transport
        .read_message(&encrypted, &mut decision_payload)
        .map_err(|error| format!("Şifreli cevap doğrulanamadı: {error}"))?;
    let decision: PairingDecisionWire = serde_json::from_slice(&decision_payload[..length])
        .map_err(|error| format!("Geçersiz eşleştirme cevabı: {error}"))?;
    if decision.accepted {
        Ok(security_code)
    } else {
        Err(if decision.reason.is_empty() {
            "Eşleştirme isteği reddedildi".to_owned()
        } else {
            decision.reason
        })
    }
}

/// Accepts or rejects a pending request through its encrypted Noise channel.
pub fn respond_to_pairing_request(request_id: String, accepted: bool) -> Result<(), String> {
    let mut slot = local_service_slot()
        .lock()
        .map_err(|_| "Yerel servis kilidi kullanılamıyor".to_owned())?;
    let service = slot
        .as_mut()
        .ok_or_else(|| "Yerel servis çalışmıyor".to_owned())?;
    let mut pending = service
        .pending
        .remove(&request_id)
        .ok_or_else(|| "Eşleştirme isteği artık beklemede değil".to_owned())?;

    let final_message: Vec<u8> = read_frame(&mut pending.stream)?;
    let mut payload = [0_u8; 1024];
    pending
        .handshake
        .read_message(&final_message, &mut payload)
        .map_err(|error| format!("Güvenli oturum tamamlanamadı: {error}"))?;
    let mut transport = pending
        .handshake
        .into_transport_mode()
        .map_err(|error| format!("Şifreli kanala geçilemedi: {error}"))?;
    let decision = serde_json::to_vec(&PairingDecisionWire {
        accepted,
        reason: if accepted {
            String::new()
        } else {
            "Karşı cihaz isteği reddetti".to_owned()
        },
    })
    .map_err(|error| error.to_string())?;
    let mut encrypted = vec![0; MAX_FRAME_SIZE];
    let length = transport
        .write_message(&decision, &mut encrypted)
        .map_err(|error| format!("Şifreli cevap oluşturulamadı: {error}"))?;
    encrypted.truncate(length);
    write_frame(&mut pending.stream, &encrypted)
}

/// Returns pending pairing requests without accepting them automatically.
pub fn poll_pairing_requests() -> Result<Vec<IncomingPairingRequest>, String> {
    let mut slot = local_service_slot()
        .lock()
        .map_err(|_| "Yerel servis kilidi kullanılamıyor".to_owned())?;
    let Some(service) = slot.as_mut() else {
        return Ok(Vec::new());
    };

    let mut requests = Vec::new();
    loop {
        let (mut stream, peer) = match service.listener.accept() {
            Ok(connection) => connection,
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => break,
            Err(error) => return Err(error.to_string()),
        };
        stream
            .set_read_timeout(Some(Duration::from_millis(500)))
            .map_err(|error| error.to_string())?;
        let request: PairingRequestWire = match read_frame(&mut stream) {
            Ok(request) => request,
            Err(_) => continue,
        };
        if request.kind != "pairing_request"
            || request.protocol_version != crate::PROTOCOL_VERSION
            || request.device_id.len() > 128
            || request.device_name.len() > 128
        {
            continue;
        }
        let params = NOISE_PARAMS
            .parse()
            .map_err(|error| format!("Güvenli protokol hazırlanamadı: {error}"))?;
        let builder = Builder::new(params);
        let keypair = builder
            .generate_keypair()
            .map_err(|error| format!("Yerel özel anahtar oluşturulamadı: {error}"))?;
        let mut handshake = builder
            .local_private_key(&keypair.private)
            .map_err(|error| format!("Yerel özel anahtar ayarlanamadı: {error}"))?
            .build_responder()
            .map_err(|error| format!("Güvenli oturum hazırlanamadı: {error}"))?;
        let mut payload = [0_u8; 1024];
        handshake
            .read_message(&request.handshake_message, &mut payload)
            .map_err(|error| format!("Güvenli istek doğrulanamadı: {error}"))?;
        let mut handshake_message = vec![0; 1024];
        let length = handshake
            .write_message(&[], &mut handshake_message)
            .map_err(|error| format!("Güvenli cevap oluşturulamadı: {error}"))?;
        handshake_message.truncate(length);
        write_frame(
            &mut stream,
            &PairingHandshakeWire {
                kind: "pairing_handshake".to_owned(),
                handshake_message,
            },
        )?;
        let security_code = security_code(handshake.get_handshake_hash());
        stream
            .set_read_timeout(Some(PAIRING_TIMEOUT))
            .map_err(|error| error.to_string())?;
        service.pending.insert(
            request.request_id.clone(),
            PendingPairing { stream, handshake },
        );
        requests.push(IncomingPairingRequest {
            request_id: request.request_id,
            device_id: request.device_id,
            device_name: request.device_name,
            protocol_version: request.protocol_version,
            address: peer.ip().to_string(),
            security_code,
        });
    }
    Ok(requests)
}

fn write_frame<T: Serialize>(stream: &mut TcpStream, value: &T) -> Result<(), String> {
    let payload = serde_json::to_vec(value).map_err(|error| error.to_string())?;
    write_bytes(stream, &payload)
}

fn write_bytes(stream: &mut TcpStream, payload: &[u8]) -> Result<(), String> {
    if payload.len() > MAX_FRAME_SIZE {
        return Err("Ağ mesajı çok büyük".to_owned());
    }
    stream
        .write_all(&(payload.len() as u32).to_be_bytes())
        .and_then(|_| stream.write_all(payload))
        .map_err(|error| error.to_string())
}

fn read_frame<T: for<'de> Deserialize<'de>>(stream: &mut TcpStream) -> Result<T, String> {
    let mut length = [0_u8; 4];
    stream
        .read_exact(&mut length)
        .map_err(|error| error.to_string())?;
    let length = u32::from_be_bytes(length) as usize;
    if length > MAX_FRAME_SIZE {
        return Err("Ağ mesajı çok büyük".to_owned());
    }
    let mut payload = vec![0; length];
    stream
        .read_exact(&mut payload)
        .map_err(|error| error.to_string())?;
    serde_json::from_slice(&payload).map_err(|error| error.to_string())
}

fn security_code(hash: &[u8]) -> String {
    hash.iter()
        .take(6)
        .map(|byte| format!("{byte:02X}"))
        .collect::<Vec<_>>()
        .join("-")
}

/// Searches the local network for Transfer services for a bounded duration.
///
/// Only services that advertise both a device id and the supported protocol
/// version are returned. Discovery metadata is not trusted for authorization.
pub fn discover_devices(timeout_ms: u32) -> Result<Vec<DiscoveredDevice>, String> {
    let daemon = ServiceDaemon::new().map_err(|error| error.to_string())?;
    let receiver = daemon
        .browse(crate::SERVICE_TYPE)
        .map_err(|error| error.to_string())?;
    let deadline = Instant::now() + Duration::from_millis(timeout_ms.max(100) as u64);
    let mut devices = BTreeMap::new();

    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            break;
        }

        let event = match receiver.recv_timeout(remaining) {
            Ok(event) => event,
            Err(_) => break,
        };

        let ServiceEvent::ServiceResolved(service) = event else {
            continue;
        };

        let Some(device_id) = service.get_property_val_str("id") else {
            continue;
        };
        let Some(protocol_version) = service.get_property_val_str("v") else {
            continue;
        };
        if protocol_version != crate::PROTOCOL_VERSION {
            continue;
        }

        // A link-local IPv6 address can contain an interface suffix such as
        // `%wlan0`, which is not a portable TCP endpoint for this app. For a
        // same-Wi-Fi transfer, prefer a usable IPv4 address and skip services
        // that do not expose one.
        let address = service
            .get_addresses_v4()
            .iter()
            .filter(|address| {
                !address.is_loopback() && !address.is_unspecified() && !address.is_link_local()
            })
            .max_by_key(|address| is_private_ipv4(address))
            .map(ToString::to_string);
        let Some(address) = address else {
            continue;
        };
        let name = mdns_sd::instance_name_unescaped(service.get_fullname());
        let platform = service
            .get_property_val_str("platform")
            .unwrap_or("Bilinmeyen cihaz")
            .to_owned();
        let device = DiscoveredDevice {
            name,
            platform,
            address,
            port: service.get_port(),
            device_id: device_id.to_owned(),
            protocol_version: protocol_version.to_owned(),
        };
        devices.insert(device.device_id.clone(), device);
    }

    let _ = daemon.shutdown();
    Ok(devices.into_values().collect())
}

fn is_private_ipv4(address: &Ipv4Addr) -> u8 {
    let [first, second, ..] = address.octets();
    u8::from(
        first == 10
            || (first == 172 && (16..=31).contains(&second))
            || (first == 192 && second == 168),
    )
}
