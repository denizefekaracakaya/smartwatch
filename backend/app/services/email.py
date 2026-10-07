"""E-mail delivery backends."""

import logging
import smtplib
import ssl
from dataclasses import dataclass
from email.message import EmailMessage
from typing import Protocol

from app.config import Settings

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class OutgoingEmail:
    to: str
    subject: str
    body: str


class EmailSender(Protocol):
    def send(self, message: OutgoingEmail) -> None: ...


class ConsoleEmailSender:
    """Development sender: logs the message and keeps it in memory (used by tests)."""

    def __init__(self) -> None:
        self.outbox: list[OutgoingEmail] = []

    def send(self, message: OutgoingEmail) -> None:
        self.outbox.append(message)
        logger.info("E-mail to %s | %s\n%s", message.to, message.subject, message.body)


class SmtpEmailSender:
    def __init__(self, settings: Settings):
        self.settings = settings

    def send(self, message: OutgoingEmail) -> None:
        msg = EmailMessage()
        msg["From"] = self.settings.email_from
        msg["To"] = message.to
        msg["Subject"] = message.subject
        msg.set_content(message.body)
        s = self.settings
        try:
            with smtplib.SMTP(s.smtp_host, s.smtp_port, timeout=10) as smtp:
                if s.smtp_starttls:
                    smtp.starttls(context=ssl.create_default_context())
                if s.smtp_username and s.smtp_password:
                    smtp.login(s.smtp_username, s.smtp_password)
                smtp.send_message(msg)
        except (OSError, smtplib.SMTPException):
            # Delivery failures must not break the request or reveal whether the account exists.
            logger.exception("Failed to send e-mail '%s'", message.subject)


def build_email_sender(settings: Settings) -> EmailSender:
    return SmtpEmailSender(settings) if settings.email_backend == "smtp" else ConsoleEmailSender()
