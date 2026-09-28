import os
from flask import Flask, Blueprint
from flask_restx import Api, Resource, fields
from flask_cors import CORS, cross_origin

authorizations = {
    'apikey': {
        'type': 'apiKey',
        'in': 'HTTP headers',
        'name': 'X-API-KEY'
    }
}
class Server(object):
    def __init__(self):
        self.app = Flask(__name__, template_folder='../templates', static_folder='../static')
        CORS(self.app)
        self.apiblueprint = Blueprint('api', __name__, url_prefix='/api/v1')
        self.api = Api(self.apiblueprint, 
            version='1',
            title='School Library API',
            description='API access to the School Library - build your own apps using this API.', 
            doc = "/docs",
            authorizations=authorizations,
            default = "/api/v1"
        )
        self.app.register_blueprint(self.apiblueprint)
        self.app.config['RESTX_MASK_SWAGGER'] = False
        self.app.config['SWAGGER_UI_DOC_EXPANSION'] = 'list'

    def run(self):
        # DEVASC-VM (ABRedes): endereço/porta configuráveis; padrão = library.demo.local (192.0.2.1:80)
        self.app.run(
                debug = False,
                host = os.environ.get('SIM_HOST', '192.0.2.1'),
                port = int(os.environ.get('SIM_PORT', '80'))
            )

server = Server()
