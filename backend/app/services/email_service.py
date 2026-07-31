# backend/app/services/email_service.py
import os
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from dotenv import load_dotenv

load_dotenv()

class EmailService:
    def __init__(self):
        self.host = os.getenv("EMAIL_HOST", "smtp.gmail.com")
        self.port = int(os.getenv("EMAIL_PORT", 587))
        self.username = os.getenv("EMAIL_USER")
        self.password = os.getenv("EMAIL_PASSWORD")
        self.from_email = os.getenv("EMAIL_FROM", self.username)
        self.tls = os.getenv("EMAIL_TLS", "True").lower() == "true"

    def send_reset_password_email(self, to_email: str, reset_url: str, token: str = None):
        """Envoie un email de réinitialisation de mot de passe"""
        
        if not self.username or not self.password:
            print(" EMAIL NOT CONFIGURED: Please set EMAIL_USER and EMAIL_PASSWORD in .env")
            print(f" Would have sent to: {to_email}")
            print(f" Reset link: {reset_url}")
            return False

        subject = " Reset Your Password - Fatigue Monitoring"
        
        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body {{ font-family: Arial, sans-serif; background-color: #f4f4f4; margin: 0; padding: 20px; }}
                .container {{ max-width: 600px; margin: 0 auto; background: white; border-radius: 12px; padding: 40px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
                .header {{ text-align: center; padding-bottom: 20px; border-bottom: 2px solid #40E0D0; }}
                .header h1 {{ color: #0A192F; margin: 0; }}
                .content {{ padding: 30px 0; }}
                .content p {{ color: #333; line-height: 1.6; }}
                .button {{ display: inline-block; background: #40E0D0; color: #0A192F; padding: 14px 32px; text-decoration: none; border-radius: 8px; font-weight: bold; margin: 20px 0; }}
                .button:hover {{ background: #36c4b6; }}
                .footer {{ text-align: center; padding-top: 20px; border-top: 1px solid #eee; font-size: 12px; color: #888; }}
                .token {{ background: #f5f5f5; padding: 10px; border-radius: 6px; font-family: monospace; font-size: 14px; }}
                .warning {{ color: #e74c3c; font-size: 13px; }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>🔐 Fatigue Monitoring</h1>
                </div>
                <div class="content">
                    <h2>Reset Your Password</h2>
                    <p>Hello,</p>
                    <p>We received a request to reset your password. Click the button below to create a new password:</p>
                    <div style="text-align: center;">
                        <a href="{reset_url}" class="button">🔄 Reset Password</a>
                    </div>
                    <p>Or copy and paste this link in your browser:</p>
                    <p><a href="{reset_url}" style="color: #40E0D0; word-break: break-all;">{reset_url}</a></p>
                    <p class="warning">⚠️ This link will expire in <strong>10 minutes</strong>.</p>
                    <p>If you didn't request this, please ignore this email.</p>
                </div>
                <div class="footer">
                    <p>Fatigue Monitoring App - Sécurité</p>
                    <p>© 2024 All rights reserved</p>
                </div>
            </div>
        </body>
        </html>
        """

        # Créer le message
        msg = MIMEMultipart('alternative')
        msg['Subject'] = subject
        msg['From'] = self.from_email
        msg['To'] = to_email
        msg.attach(MIMEText(html_content, 'html'))

        try:
            # Connexion au serveur SMTP
            if self.tls:
                server = smtplib.SMTP(self.host, self.port)
                server.starttls()
            else:
                server = smtplib.SMTP_SSL(self.host, self.port)
            
            server.login(self.username, self.password)
            server.send_message(msg)
            server.quit()
            
            print(f" Email sent to {to_email}")
            return True
            
        except Exception as e:
            print(f" Failed to send email: {e}")
            print(f" Would have sent to: {to_email}")
            print(f" Reset link: {reset_url}")
            return False

# Instance unique
email_service = EmailService()