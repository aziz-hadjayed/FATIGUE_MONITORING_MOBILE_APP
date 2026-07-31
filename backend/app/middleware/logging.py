import logging
import time
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger("fastapi")

class LoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start = time.time()
        client_ip = request.client.host
        method = request.method
        path = request.url.path
        
        response = await call_next(request)
        
        duration = time.time() - start
        status = response.status_code
        
        # Log pour Fail2Ban : METHOD PATH STATUS client IP duration
        logger.info(f'{method} {path} {status} client {client_ip} {duration:.3f}s')
        
        return response