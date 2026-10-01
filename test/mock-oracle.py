#!/usr/bin/env python3
"""Stands in for the OnionDAO oracle in CI: validates the registration payload and answers like the real one."""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

REQUIRED = { 'ip', 'email', 'bandwidth', 'reduced_exit_policy', 'node_nickname', 'wallet' }

class Oracle( BaseHTTPRequestHandler ):

    def do_POST( self ):
        body = self.rfile.read( int( self.headers.get( 'Content-Length', 0 ) ) )
        try:
            payload = json.loads( body )
            missing = REQUIRED - payload.keys()
            if missing: raise ValueError( f'missing { sorted( missing ) }' )
            with open( '/tmp/oracle-request.json', 'w' ) as f: json.dump( payload, f )
            answer = '✅ OnionDAO Oracle successfully registered your node'
        except Exception as e:
            answer = f'🛑 OnionDAO Oracle error: { e }'
        self.send_response( 200 )
        self.end_headers()
        self.wfile.write( answer.encode() )

    def log_message( self, *args ): pass

HTTPServer( ( '127.0.0.1', int( sys.argv[ 1 ] if len( sys.argv ) > 1 else 8099 ) ), Oracle ).serve_forever()
