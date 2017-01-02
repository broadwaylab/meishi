class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # , :encryptable, :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable, :token_authenticatable

  # Setup accessible (or protected) attributes for your model
  attr_accessible :username, :email, :password, :password_confirmation, :remember_me

  validates_presence_of :username
  validates_uniqueness_of :username

  has_many :address_books, :dependent => :destroy

  before_save :generate_auth_token, unless: :auth_token? 

  def quota_used_bytes
    Field.joins(:address_book)
         .where('address_books.user_id' => self.id)
         .inject(0) {|ret, field| ret += (field.name.length + field.value.length)}
  end

  def self.search(email)
    if email
      where('email LIKE ?', "%#{email}%")
    else
      scoped
    end
  end

  private

  def generate_auth_token
    self.auth_token = SecureRandom.uuid
  end
end
