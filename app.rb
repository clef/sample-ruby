require 'sinatra'
require 'httparty'
require 'json'

require_relative 'models/user'

##
# Configuration for the application
#
configure do
    enable :sessions, :logging
    set :session_secret, 'REPLACE THIS IN YOUR APP'
    set :clef_api_base, 'https://clef.io/api/v1'
    set :clef_app_id, '58247f018c3fdac32abdacddfcfaf8fc'
    set :clef_app_secret, '2ef51ea751ae2bb36ffdb2a63016c6bb'
end

##
# Check if the user is in the session or has been logged out by Clef
#
# Read more about how this works here: http://docs.getclef.com/v1.0/docs/overview
#
before do
    if session[:user] and @user = User.get(session[:user])
        if session[:logged_in_at] and @user.logged_out_at and @user.logged_out_at > session[:logged_in_at]
            @user = nil
            session.delete(:logged_in_at)
            session.delete(:user)
        end
    end
end

##
# Render the index template which either shows the Clef button or user information
#
get '/' do
    erb :index
end

##
# Receive the Clef login callback and log the user in.
#
# Read more here: http://docs.getclef.com/v1.0/docs/authenticating-users
#
get '/callback/login' do
    return redirect to('/') if @user

    code = params[:code]
    data = {
        body: {
            code: code,
            app_id: settings.clef_app_id,
            app_secret: settings.clef_app_secret
        }
    }

    response = HTTParty.post("#{settings.clef_api_base}/authorize", data)

    if response['success']
        access_token = response['access_token']

        url = "#{settings.clef_api_base}/info?access_token=#{access_token}"
        response = HTTParty.get(url)

        if response['success']

            info = response['info']
            unless @user = User.first(clef_id: info['id'])
                @user = User.create(
                    email: info['email'],
                    clef_id: info['id']
                )
            end

            session[:logged_in_at] = Time.now.to_i
            session[:user] = @user.id

            redirect to('/')
        else
            status 500
            response['error']
        end
    else
        status 500
        response['error']
    end
end

##
# Receive the Clef logout webhook and log the user out.
#
# Read more here: http://docs.getclef.com/v1.0/docs/handling-the-logout-webhook
#
post '/callback/logout' do
    content_type :json

    data = {
        body: {
            logout_token: params[:logout_token],
            app_id: settings.clef_app_id,
            app_secret: settings.clef_app_secret
        }
    }

    response = HTTParty.post("#{settings.clef_api_base}/logout", data)

    if response['success']
        user = User.first(clef_id: response['clef_id'])
        user.update(logged_out_at: Time.now.to_i)
        { success: true }.to_json
    else
        status 500
        { error: response['error'] }.to_json
    end
end