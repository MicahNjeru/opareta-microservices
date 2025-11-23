import { ApiProperty } from '@nestjs/swagger';
import {
  IsNotEmpty,
  IsEnum,
  IsString,
  IsDateString,
} from 'class-validator';
import { PaymentStatus } from '../entities/payment.entity';

export class WebhookDto {
  @ApiProperty({
    example: '550e8400-e29b-41d4-a716-446655440000',
    description: 'Payment reference',
  })
  @IsNotEmpty()
  @IsString()
  payment_reference: string;

  @ApiProperty({
    example: 'SUCCESS',
    enum: PaymentStatus,
    description: 'Payment status from provider',
  })
  @IsNotEmpty()
  @IsEnum(PaymentStatus)
  status: PaymentStatus;

  @ApiProperty({
    example: 'TXN123456789',
    description: 'Provider transaction ID',
  })
  @IsNotEmpty()
  @IsString()
  provider_transaction_id: string;

  @ApiProperty({
    example: '2024-01-01T12:00:00Z',
    description: 'Webhook timestamp',
  })
  @IsNotEmpty()
  @IsDateString()
  timestamp: string;
}