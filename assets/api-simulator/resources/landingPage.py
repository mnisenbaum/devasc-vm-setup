from flask import Flask, render_template

from server.instance import server
app, api = server.app, server.api

@app.route('/')
def landingPage():
    return render_template('index.html')