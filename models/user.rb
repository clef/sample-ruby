require 'data_mapper'

DataMapper.setup(:default, 'sqlite::memory:')

class User
  include DataMapper::Resource

  property :id,         Serial        # An auto-increment integer key
  property :email,      String        # The user's email
  property :clef_id,    Integer       # The user's Clef ID
  property :logged_out_at, Integer    # When the user was last logged out by Clef
end

DataMapper.auto_upgrade!
