import { ApiProperty } from '@nestjs/swagger';
import { PaymentStatus, Currency, PaymentMethod } from '../entities/payment.entity';

export class PaymentResponseDto {
  @ApiProperty({ example: '123e4567-e89b-12d3-a456-426614174000' })
  id: string;

  @ApiProperty({ example: '550e8400-e29b-41d4-a716-446655440000' })
  reference: string;

  @ApiProperty({ example: 10000 })
  amount: number;

  @ApiProperty({ example: 'KES', enum: Currency })
  currency: Currency;

  @ApiProperty({ example: 'MOBILE_MONEY', enum: PaymentMethod })
  payment_method: PaymentMethod;

  @ApiProperty({ example: '+254700000000' })
  customer_phone: string;

  @ApiProperty({ example: 'customer@example.com' })
  customer_email: string;

  @ApiProperty({ example: 'INITIATED', enum: PaymentStatus })
  status: PaymentStatus;

  @ApiProperty({ example: 'TXN123456789', required: false })
  provider_transaction_id?: string;

  @ApiProperty({ example: '2024-01-01T00:00:00.000Z' })
  created_at: Date;

  @ApiProperty({ example: '2024-01-01T00:00:00.000Z' })
  updated_at: Date;
}

export class WebhookResponseDto {
  @ApiProperty({ example: true })
  success: boolean;

  @ApiProperty({ example: 'Webhook processed successfully' })
  message: string;

  @ApiProperty({ example: '550e8400-e29b-41d4-a716-446655440000' })
  payment_reference: string;
}