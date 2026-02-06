#!/usr/bin/env python3
import http.server
import ssl
import os

# Change to web directory
os.chdir('web')

# Create server
server_address = ('0.0.0.0', 8443)
httpd = http.server.HTTPServer(server_address, http.server.SimpleHTTPRequestHandler)

# Wrap with SSL
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('server.pem')

httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

print(f'Servidor HTTPS rodando em https://0.0.0.0:8443')
print('Acesse pelo iPhone usando o IP local da máquina')
httpd.serve_forever()
