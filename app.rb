require 'sinatra'
require 'httparty'
require 'json'
require 'data_mapper'

DataMapper.setup(:default, 'sqlite::memory:')

class User
  include DataMapper::Resource

  property :id,         Serial    # An auto-increment integer key
  property :email,      String    # The user's email
  property :clef_id,    Integer   # The user's Clef ID
end

DataMapper.auto_upgrade!

APP_ID = '58247f018c3fdac32abdacddfcfaf8fc'
APP_SECRET = '2ef51ea751ae2bb36ffdb2a63016c6bb'

enable :sessions, :logging

get '/' do
    @user = User.get(session[:user]) if session[:user]
    erb :index
end

get '/logout' do
    session.delete(:user)
    erb :index
end

get '/login' do
    code = params[:code]
    p code
    data = {
        body: {
            code: code,
            app_id: APP_ID,
            app_secret: APP_SECRET
        }
    }

    url = "https://clef.io/api/v1/authorize"

    response = HTTParty.post(url, data)

if response['success']
    access_token = response['access_token']

    url = "https://clef.io/api/v1/info?access_token=#{access_token}"

    response = HTTParty.get(url)

    if response['success']
        info = response['info']
        unless @user = User.first(clef_id: info['id'])
            @user = User.create(
                email: info['email'],
                clef_id: info['id']
            )
        end
        session[:user] = @user.id
        erb :index
    else
        p response['error']
    end
else
    p response['error']
end
end