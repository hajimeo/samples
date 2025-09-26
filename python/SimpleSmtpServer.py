# @see: https://stackoverflow.com/questions/45447491/how-do-i-properly-support-starttls-with-aiosmtpd
# openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 3650 -nodes -subj '/CN=localhost'

import asyncio
import ssl
import sys

from aiosmtpd.smtp import SMTP
from aiosmtpd.controller import Controller
from aiosmtpd.handlers import Debugging


# Pass SSL context to aiosmtpd
class ControllerStarttls(Controller):
    def factory(self):
        return SMTP(self.handler, require_starttls=True, tls_context=context)


async def main(port=587, hostname='localhost'):
    controller = ControllerStarttls(Debugging(), port=port, hostname=hostname)
    controller.start()
    print(f"SMTP server started on {controller.hostname}:{controller.port}")
    print(f"Connection test: echo -n | openssl s_client -servername {controller.hostname} -connect {controller.hostname}:{controller.port} -starttls smtp")

    try:
        # Keep the server running until interrupted
        await asyncio.Future()
    except KeyboardInterrupt:
        pass
    finally:
        controller.stop()
        print("SMTP server stopped.")


if __name__ == '__main__':
    listen_port = 38587
    if len(sys.argv) > 1 and len(sys.argv[1]) > 0:
        listen_port = sys.argv[1]

    # Load SSL context
    context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    context.load_cert_chain('cert.pem', 'key.pem')

    print(f"Listening on :{listen_port} ...")
    print('Starting server, use <Ctrl-C> to stop')
    asyncio.run(main(port=listen_port))
