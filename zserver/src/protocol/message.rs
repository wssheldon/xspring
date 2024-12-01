use std::collections::HashMap;

#[derive(Debug)]
pub struct ProtocolMessage {
    pub version: u32,
    pub msg_type: u32,
    pub fields: HashMap<String, String>,
}

impl ProtocolMessage {
    pub fn parse(data: &str) -> Option<Self> {
        let mut lines = data.lines();
        let mut message = Self {
            version: 0,
            msg_type: 0,
            fields: HashMap::new(),
        };

        if let Some(version_line) = lines.next() {
            if let Some(version_str) = version_line.strip_prefix("Version: ") {
                message.version = version_str.parse().ok()?;
            } else {
                return None;
            }
        }

        if let Some(type_line) = lines.next() {
            if let Some(type_str) = type_line.strip_prefix("Type: ") {
                message.msg_type = type_str.parse().ok()?;
            } else {
                return None;
            }
        }

        for line in lines {
            if let Some((key, value)) = line.split_once(": ") {
                message.fields.insert(key.to_string(), value.to_string());
            }
        }

        Some(message)
    }
}
