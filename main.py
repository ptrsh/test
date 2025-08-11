import os
from dotenv import load_dotenv
from app import create_app

# Загрузка переменных окружения
load_dotenv()

app = create_app()

if __name__ == '__main__':
    app.run(
        host='0.0.0.0',
        port=int(os.getenv('PORT', 5000)),
        debug=os.getenv('FLASK_ENV') == 'development'
    )
