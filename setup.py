from setuptools import setup

setup(
    name='primechoice',
    version='1.0',
    install_requires=[
        'Django==4.1.6',
        'psycopg2-binary',
        'python-dotenv',
        'dj-database-url'
    ],
)