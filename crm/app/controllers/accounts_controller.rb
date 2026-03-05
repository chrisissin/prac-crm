class AccountsController < ApplicationController
  before_action :require_login
  before_action :set_account, only: [:show, :edit, :update, :destroy]

  def index
    @accounts = Account.order(:name).page(params[:page]).per(20)
  end

  def show
    @contacts = @account.contacts
    @deals = @account.deals
  end

  def new
    @account = Account.new
  end

  def create
    @account = Account.new(account_params)
    if @account.save
      redirect_to @account, notice: "Account created."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @account.update(account_params)
      redirect_to @account, notice: "Account updated."
    else
      render :edit
    end
  end

  def destroy
    @account.destroy
    redirect_to accounts_path, notice: "Account deleted."
  end

  private

  def set_account
    @account = Account.find(params[:id])
  end

  def account_params
    params.require(:account).permit(:name, :industry, :phone, :email, :address, :status)
  end
end
