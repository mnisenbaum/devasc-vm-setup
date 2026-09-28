from flask import Flask, request, make_response
from flask_restx import Api, Resource, fields
from flask_restx import reqparse
from flask_restx import inputs

from server.instance import server
from models.bookModel import bookModel
from models.userCredentialsModel import userCredentialsModel

import json
import yaml
import secrets
from functools import wraps 
import dicttoxml

from faker import Faker
from time import time

app, api = server.app, server.api

books_db = [
    {"id": 0, "title": "IP Routing Fundamentals", "author": "Mark A. Sportack", "isbn":"978-1578700714"},
    {"id": 1, "title": "Python for Dummies", "author": "Stef Maruch Aahz Maruch", "isbn":"978-0471778646"},
    {"id": 2, "title": "Linux for Networkers", "author": "Cisco Systems Inc.", "isbn":"000-0000000123"},
    {"id": 3, "title": "NetAcad: 20 Years Of Online-Learning", "author": "Cisco Systems Inc.", "isbn":"000-0000001123"},
]

#fake = Faker()
#for i in range(4, 105):
#    fakeTitle = fake.catch_phrase()
#    fakeAuthor = fake.name()
#    fakeISBN = fake.isbn13()
#    book = {"id":i, "title": fakeTitle, "author": fakeAuthor, "isbn": fakeISBN}
#    books_db.append(book)

# Rate Limits
pageRequestsInBucket = {}

users_db = [
    {"u":"cisco", "p":"Cisco123!"}
]

tokens_db = []

def addNewAuthToken(username):
    token = username+"|"+secrets.token_urlsafe()
    tokens_db.append(token)
    return token
def verifyToken(token):
    return token in tokens_db

def apikeyTokenRequired(func):
    func = api.doc(security='apikey')(func)
    @wraps(func)
    def checkToken(*args, **kwargs):
        if 'X-API-KEY' not in request.headers:
            return {'error': 'API key required'}, 400
        key = request.headers['X-API-KEY']
        if not verifyToken(key):
            return {'error': 'Invalid API key'}, 401
        return func(*args, **kwargs)
    return checkToken
def apiRateLimit(func):
    @wraps(func)
    def rateLimit(*args, **kwargs):
        # Rate-limiting https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.37
        global pageRequestsInBucket
        # bucket lifetime block - when a new bucket is ready (seconds)
        bucketLifetime = 10 
        # max queries in a single bucket
        rateLimit = 5
        # create new buckets at new Litetime blocks
        nowBucket = int(time()/bucketLifetime)*bucketLifetime
        # check if the current bucket exists
        if not nowBucket in pageRequestsInBucket:
            pageRequestsInBucket[nowBucket] = 0
        if pageRequestsInBucket[nowBucket] > rateLimit:
            headers = {
                    "Retry-After": int(time()/bucketLifetime)*bucketLifetime + bucketLifetime - int(time()), 
                    "X-RateLimit-Limit": rateLimit, 
                    "X-RateLimit-BucketLifetime": bucketLifetime
                    }
            return {"error":"Too many requests."}, 429, headers
        # increase the number of requests in the bucket
        pageRequestsInBucket[nowBucket] += 1
        return func(*args, **kwargs)
    return rateLimit


@api.representation('application/xml')
def responseToXml(data, code, headers=None):
    resp = make_response(dicttoxml.dicttoxml(data), code)   
    resp.headers.extend(headers or {})
    return resp
@api.representation('application/yaml')
def responseToYaml(data, code, headers=None):
    resp = make_response(yaml.dump(data, default_flow_style=False, default_style=''), code)   
    resp.headers.extend(headers or {})
    return resp

from flask_httpauth import HTTPBasicAuth
authBasic = HTTPBasicAuth()

@authBasic.verify_password
def verifyUsersCredentials(username, password):
    for user in users_db:
        if user["u"] == username and user["p"] == password:
            return True
    return False

@api.route('/loginViaBasic', methods = ['POST'])
class LoginViaBasic(Resource):
    @api.header('Authorization: Basic', "BASE64 encoded username:password", required=True)
    @authBasic.login_required
    def post(self):
        token = addNewAuthToken(authBasic.username())
        return { 'token': token }, 200

@api.route('/loginViaJSON', methods = ['POST'])
class LoginViaJSON(Resource):
    @api.expect(userCredentialsModel, validate=True)
    def post(self):
        username = api.payload.get("username")
        password = api.payload.get("password")
        if verifyUsersCredentials(username, password):
            token = addNewAuthToken(username)
            return { 'token': token }, 200
        return {"error":"Incorrect username or password"}, 401

@api.doc("Get the list of all books from our library.")
@api.route('/books')
class Books(Resource):
    argParser = reqparse.RequestParser()
    argParser.add_argument('includeISBN', type=inputs.boolean, help='Include in the results the ISBN numbers. Default=false')
    argParser.add_argument('sortBy', type=str, help='Sort results using the specified parameter. Default=id', choices=('id', 'title', 'author', 'isbn'))
    argParser.add_argument('author', type=str, help='Return only books by the given Author.')
    argParser.add_argument('page', type=int, help='To save resources and bandwidth, larger replies might be broken down into smaller pages with 10 reconds per page. The <a href="http://tools.ietf.org/html/rfc5988">RFC5988 (Web Linking)</a> standard in HTTP Reply Headers is used for pagination.<br/> The "page" parameter is then used to specify the page number.')

    def find_one(self, id):
        return next((b for b in books_db if b["id"] == id), None)
        
    #@api.marshal_list_with(bookModel)
    @apiRateLimit
    @api.expect(argParser)
    def get(self):
        # Pagination https://developer.webex.com/docs/api/basics#pagination
        numberOfBooks = len(books_db)
        maxBooksPerPage = 10
        numberOfPages = numberOfBooks // maxBooksPerPage
        parser = reqparse.RequestParser()
        parser.add_argument('page', type=int)
        page = parser.parse_args().get('page')
        parser.add_argument('includeISBN', type=inputs.boolean)
        includeISBN = parser.parse_args().get('includeISBN')
        parser.add_argument('sortBy', type=str, default='id', choices=('id', 'title', 'author', 'isbn'))
        sortBy = parser.parse_args().get('sortBy')
        parser.add_argument('author', type=str)
        author = parser.parse_args().get('author')

        page = page if page else 0
        paginationHeader = {}
        if page < numberOfPages:
            paginationHeader = {"Link": f'<http://library.demo.local/api/v1/books?page={page+1}>; rel="next"'}
        # pagination:
        books_db_page = books_db[page*maxBooksPerPage:page*maxBooksPerPage+maxBooksPerPage]

        if sortBy == "title":
            books_db_page = sorted(books_db_page, key = lambda i: i['title'])
        elif sortBy == "author":
            books_db_page = sorted(books_db_page, key = lambda i: i['author'])
        elif sortBy == "isbn":
            books_db_page = sorted(books_db_page, key = lambda i: i['isbn'])
        else:
            books_db_page = sorted(books_db_page, key = lambda i: i['id'])

        if author:
            books_db_page = [book for book in books_db_page if book['author'] == author]
        
        if not includeISBN:
            # only return basic book info for all books. Details via /rooms/<id>
            books_db_page = [{"id":book['id'],  "title":book['title'], "author":book['author']} for book in books_db_page]
        
        return books_db_page, 200, paginationHeader


    @apikeyTokenRequired
    @api.expect(bookModel, validate=True)
    @api.marshal_with(bookModel)
    def post(self):
        #api.payload["id"] = books_db[-1]["id"] + 1 if len(books_db) > 0 else 0
        #books_db.append(api.payload)
        match = self.find_one(api.payload["id"])
        if match != None:
            match.update(api.payload)
        else:
            books_db.append(api.payload)
            return api.payload

@api.route('/books/<int:id>')
class Book(Resource):
    def find_one(self, id):
        return next((b for b in books_db if b["id"] == id), None)

    
    @api.marshal_with(bookModel)
    def get(self, id):
        match = self.find_one(id)
        return match if match else ("Not found", 404)

    @apikeyTokenRequired
    @api.marshal_with(bookModel)
    def delete(self, id):
        global books_db 
        match = self.find_one(id)
        books_db = list(filter(lambda b: b["id"] != id, books_db))
        return match

    @apikeyTokenRequired
    @api.expect(bookModel, validate=True)
    @api.marshal_with(bookModel)
    def put(self, id):
        match = self.find_one(id)
        if match != None:
            match.update(api.payload)
            match["id"] = id
        return match

