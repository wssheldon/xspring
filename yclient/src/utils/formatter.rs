/// Functions for formatting command output

/// Format ls command output with icons and better readability
pub fn format_ls_output(output: &str) -> String {
    if !output.contains("Directory listing of") {
        return output.to_string(); // Not an LS command output
    }

    let mut formatted = String::new();
    let lines: Vec<&str> = output.lines().collect();

    // Process the directory listing header
    if let Some(first_line) = lines.first() {
        if first_line.contains("Directory listing of") {
            let clean_header = first_line.replace("\\n", "").replace("\\:", ":");
            formatted.push_str(&format!("📂 {}\n\n", clean_header));
        }
    }

    // Process each line
    for line in &lines {
        if line.trim().is_empty() || line.contains("Directory listing of") {
            continue;
        }

        if line.contains("Completed:") {
            formatted.push_str(&format!("\n{}", line));
            continue;
        }

        // Clean up the line
        let clean_line = line.replace("\\n", "").replace("\\:", ":");

        // Try to extract useful info
        if clean_line.contains("NSFileTypeDirectory") {
            // Format directories
            if let Some(name) = extract_filename_from_line(&clean_line) {
                formatted.push_str(&format!("  📁 Directory: {}\n", name));
            } else {
                formatted.push_str(&format!("  📁 {}\n", clean_line));
            }
        } else if clean_line.contains("NSFileTypeRegular") {
            // Format regular files
            if let Some(name) = extract_filename_from_line(&clean_line) {
                if let Some(size) = extract_file_size(&clean_line) {
                    formatted.push_str(&format!("  📄 File: {} ({})\n", name, size));
                } else {
                    formatted.push_str(&format!("  📄 File: {}\n", name));
                }
            } else {
                formatted.push_str(&format!("  📄 {}\n", clean_line));
            }
        } else {
            // Other entries
            formatted.push_str(&format!("  • {}\n", clean_line));
        }
    }

    formatted
}

/// Helper function to extract filename from a line
pub fn extract_filename_from_line<'a>(line: &'a str) -> Option<&'a str> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    if parts.is_empty() {
        return None;
    }

    // The path is usually at the end after +0000
    let last_part = *parts.last().unwrap();
    if last_part.contains('/') {
        return last_part.split('/').last();
    }

    Some(last_part)
}

/// Helper function to extract file size
pub fn extract_file_size<'a>(line: &'a str) -> Option<&'a str> {
    if let Some(pos) = line.find("bytes") {
        let start = line[..pos].rfind(' ').map(|p| p + 1).unwrap_or(0);
        return Some(&line[start..pos].trim());
    }
    None
}
