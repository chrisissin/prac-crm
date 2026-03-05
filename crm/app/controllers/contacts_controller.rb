class ContactsController < ApplicationController
  before_action :require_login
  before_action :set_contact, only: [:show, :edit, :update, :destroy]

  def index
    @contacts = Contact.includes(:account).order(:last_name).page(params[:page]).per(20)
  end

  def show
  end

  def new
    @contact = Contact.new
  end

  def create
    @contact = Contact.new(contact_params)
    if @contact.save
      redirect_to @contact, notice: "Contact created."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @contact.update(contact_params)
      redirect_to @contact, notice: "Contact updated."
    else
      render :edit
    end
  end

  def destroy
    @contact.destroy
    redirect_to contacts_path, notice: "Contact deleted."
  end

  private

  def set_contact
    @contact = Contact.find(params[:id])
  end

  def contact_params
    params.require(:contact).permit(:first_name, :last_name, :title, :email, :phone, :account_id)
  end
end
