#!/bin/bash
# Script to generate self-signed SSL certificates for development

# Create certs directory if it doesn't exist
mkdir -p certs

# Generate a private key
openssl genrsa -out certs/server.key 2048

# Generate a certificate signing request
openssl req -new -key certs/server.key -out certs/server.csr -subj "/C=US/ST=State/L=City/O=Organization/CN=127.0.0.1"

# Generate a self-signed certificate valid for 365 days
openssl x509 -req -days 365 -in certs/server.csr -signkey certs/server.key -out certs/server.crt

# Add Subject Alternative Name (SAN) for both localhost and 127.0.0.1
cat > certs/openssl.cnf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = 127.0.0.1

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
EOF

# Generate a new certificate with SAN extension
openssl x509 -req -days 365 -in certs/server.csr -signkey certs/server.key -out certs/server.crt -extfile certs/openssl.cnf -extensions v3_req

# Clean up the CSR as it's no longer needed
rm certs/server.csr certs/openssl.cnf

# Set permissions
chmod 600 certs/server.key
chmod 644 certs/server.crt

echo "Self-signed certificates generated successfully in the certs directory."
echo "For production use, replace these with certificates from a trusted CA." 