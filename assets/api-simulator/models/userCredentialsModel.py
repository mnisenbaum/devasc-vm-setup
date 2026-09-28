from flask_restx import fields
from server.instance import server

userCredentialsModel = server.api.model('Credentials', {
    'username': fields.String(required=True, min_length=1, max_length=32, description='Username'),
    'password': fields.String(required=True, min_length=1, max_length=200, description='Password')
})