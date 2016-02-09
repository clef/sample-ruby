# Clef + Ruby
![license:mit](https://img.shields.io/badge/license-mit-blue.svg)

## Getting started
Clef is secure two-factor auth without passwords. With the wave of their phone, users can log in to your site — it's like :sparkles: magic :sparkles:! 

Get started in three easy steps:
* Download the [iOS](https://itunes.apple.com/us/app/clef/id558706348) or [Android](https://play.google.com/store/apps/details?id=io.clef&hl=en) app on your phone 
* Sign up for a Clef developer account at [https://www.getclef.com/developer](https://www.getclef.com/developer) and create an application. That's where you'll get your API credentials (`app_id` and `app_secret`) and manage settings for your Clef integration.
* Follow the directions below to integrate Clef into your site's log in flow. 

## Usage
We'll walk you through the full Clef integration with Ruby and Sinatra below. You can also run this sample app [locally](#running-this-sample-app).

### Adding the Clef button

The Clef button is the entry point into the Clef experience. Adding it to your site is as easy as dropping a `script` tag wherever you want the button to show up. 

Set the `data-redirect-url` to the URL in your app where you will complete the OAuth handshake. You'll also want to set `data-state` to an unguessable random string. <br>

```javascript
<script type='text/javascript'
    class='clef-button'
    src='https://clef.io/v3/clef.js'
    data-app-id='<%= settings.clef_app_id %>'
    data-redirect-url='<%= url("callback/login") %>'
    data-state='<%= state_parameter %>'>
</script>
```
*See the code in [action](/views/index.erb#L13-L18) or read more [here](http://docs.getclef.com/v1.0/docs/adding-the-clef-button).*<br>

### Completing the OAuth handshake
Once you've set up the Clef button, you need to be able to handle the OAuth handshake. This is what lets you retrieve information about a user after they authenticate with Clef. The easiest way to do this is to use the `oauth2` gem.

To use it, pass your `app_id` and `app_secret` to the OAuth2 constructor. Then,
t the route you created for the OAuth callback, access the `code` URL parameter and exchange it for user information. 

Before exchanging the `code` for user information, you first need to verify the `state` parameter sent to the callback to make sure it's the same one as the one you set in the button. (You can find implementations of the <code><a href="/app.rb#L27-L33" target="_blank">validate_state!</a></code> and <code><a href="/app.rb#L19-L25" target="_blank">state_parameter</a></code> functions in in `app.rb`.) 

```ruby
get '/callback/login' do
  validate_state!

  return redirect to('/') if @user

  oauth_client = OAuth2::Client.new(
    settings.clef_app_id,
    settings.clef_app_secret,
    site: 'https://clef.io/api/v1',
    token_url: 'authorize'
  )

  begin
    access_token = oauth_client.auth_code.get_token(
      params[:code],
      {}, # don't pass in any params
      param_name: 'access_token',
      mode: :query
    )

    data = access_token.get('info').parsed
    info = data['info']

    unless @user = User.first(clef_id: info['id'])
      @user = User.create(
        email: info['email'],
        clef_id: info['id']
      )
    end

    session[:logged_in_at] = Time.now.to_i
    session[:user] = @user.id

    redirect to('/')
  rescue OAuth2::Error => e
    status 500
    case e.code
      # handle errors 
      when "Invalid OAuth Code." then
        'Invalid OAuth Code. This could happen if the code has already been consumed or has expired.'
      when "Invalid App ID." then
        'Invalid App ID. This could happen if you are not passing in a valid Clef application ID.'
      when "Invalid App Secret." then
        'Invalid App Secret. This could happen if you are not passing in a valid Clef application secret or it does not match the application ID you are passing in.'
      else
        e.to_s
    end
  end

end
```
*See the code in [action](/app.rb#L62-L110) or read more [here](http://docs.getclef.com/v1.0/docs/authenticating-users).*<br>

### Logging users out 
Logout with Clef allows users to have complete control over their authentication sessions. Instead of users individually logging out of each site, they log out once with their phone and are automatically logged out of every site they used Clef to log into.

To make this work, you need to [set up](#setting-up-timestamped-logins) timestamped logins, handle the [logout webhook](#handling-the-logout-webhook) and [compare the two](#checking-timestamped-logins) every time you load the user from your database. 

#### Setting up timestamped logins
Setting up timestamped logins is easy. You just add a timestamp to the session everywhere in your application code that you do the Clef OAuth handshake:

```ruby
session[:logged_in_at] = Time.now.to_i
```

*See the code in [action](/app.rb#L92) or read more [here](http://docs.getclef.com/v1.0/docs/checking-timestamped-logins)*

#### Handling the logout webhook
Every time a user logs out of Clef on their phone, Clef will send a `POST` to your logout hook with a `logout_token`. You can exchange this for a Clef ID:

```ruby
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
    user = User.first(clef_id: response['clef_id'].to_s)
    user.update(logged_out_at: Time.now.to_i)
    { success: true }.to_json
  else
    status 500
    { error: response['error'] }.to_json
  end
end

```
*See the code in [action](/app.rb#L117-L138) or read more [here](http://docs.getclef.com/v1.0/docs/handling-the-logout-webhook).*<br>

You'll want to make sure you have a `logged_out_at` attribute on your `User` model. Also, don't forget to specify this URL as the `logout_hook` in your Clef application settings so Clef knows where to notify you.

#### Checking timestamped logins
Every time you load user information from the database, you'll want to compare the `logged_in_at` session variable to the user `logged_out_at` field. If `logged_out_at` is after `logged_in_at`, the user's session is no longer valid and they should be logged out of your application.

```ruby
before do
  if session[:user] and @user = User.get(session[:user])
    if session[:logged_in_at] and @user.logged_out_at and @user.logged_out_at > session[:logged_in_at]
      @user = nil
      session.delete(:logged_in_at)
      session.delete(:user)
    end
  end
end
```
*See the code in action [here](/app.rb#L40-L48) or read more [here](http://docs.getclef.com/v1.0/docs/checking-timestamped-logins)*

## Running this sample app 
To run this sample app, clone the repo:

```
$ git clone https://github.com/clef/sample-ruby.git
```

Then install the dependencies and run on localhost:4567.
```
$ bundle install
$ ruby app.rb
```

## Documentation
You can find our most up-to-date documentation at [http://docs.getclef.com](http://docs.getclef.com/). It covers additional topics like customizing the Clef button and testing your integration.

## Support
Have a question or just want to chat? Send an email to [support@getclef.com](mailto: support@getclef.com) or join our community Slack channel :point_right: [http://community.getclef.com](http://community.getclef.com).

We're always around, but we do an official Q&A every Friday from 10am to noon PST :) — would love to see you there! 

## About 
Clef is an Oakland-based company building a better way to log in online. We power logins on more than 80,000 websites and are building a beautiful experience and inclusive culture. Read more about our [values](https://getclef.com/values), and if you like what you see, come [work with us](https://getclef.com/jobs)!



