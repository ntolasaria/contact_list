class Contact
  attr_reader :name, :phone, :email, :uid

  def validate_set_and_return_error(uid, name, phone, email=nil)
    if valid_name(name) && valid_phone(phone)
      @uid = uid
      @name = name
      @phone = phone
      @email = email if email
      nil
    else
      "Please enter valid contact details"
    end
  end

  def to_hash
    hash = {uid: uid, name: name, phone: phone}
    hash[:email] = email if email
    hash
  end

  private

  def valid_name(name)
    !name.strip.empty?
  end

  def valid_phone(phone)
    !!phone.match(/\A\d{10}\z/)
  end
end