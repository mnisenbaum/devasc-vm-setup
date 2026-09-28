from server.instance import server
import sys, os

# Need to import all resources
from resources.landingPage import *
from resources.apis import *


if __name__ == '__main__':
    server.run()