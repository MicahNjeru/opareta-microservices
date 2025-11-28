import { ApiProperty } from '@nestjs/swagger';
import {
  IsNotEmpty,
  IsNumber,
  IsEnum,
  IsEmail,
  IsString,
  Min,
  Matches,
} from 'class-validator';
import { Currency, PaymentMethod } from '../entities/payment.entity';

export class CreatePaymentDto {
  @ApiProperty({
    example: 10000,
    description: 'Payment amount',
    minimum: 0.01,
  })
  @IsNotEmpty()
  @IsNumber()
  @Min(0.01, { message: 'Amount must be greater than 0' })
  amount: number;

  @ApiProperty({
    example: 'UGX',
    enum: Currency,
    description: 'Payment currency',
  })
  @IsNotEmpty()
  @IsEnum(Currency)
  currency: Currency;

  @ApiProperty({
    example: 'MOBILE_MONEY',
    enum: PaymentMethod,
    description: 'Payment method',
  })
  @IsNotEmpty()
  @IsEnum(PaymentMethod)
  payment_method: PaymentMethod;

  @ApiProperty({
    example: '+256700000000',
    description: 'Customer phone number',
  })
  @IsNotEmpty()
  @IsString()
  @Matches(/^\+?[1-9]\d{1,14}$/, {
    message: 'Phone number must be in valid international format',
  })
  customer_phone: string;

  @ApiProperty({
    example: 'customer@example.com',
    description: 'Customer email address',
  })
  @IsNotEmpty()
  @IsEmail()
  customer_email: string;
}