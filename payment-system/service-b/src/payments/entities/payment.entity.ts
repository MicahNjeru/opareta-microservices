import {
  Entity,
  Column,
  PrimaryGeneratedColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';

export enum PaymentStatus {
  INITIATED = 'INITIATED',
  PENDING = 'PENDING',
  SUCCESS = 'SUCCESS',
  FAILED = 'FAILED',
}

export enum Currency {
  KES = 'KES',
  USD = 'USD',
}

export enum PaymentMethod {
  MOBILE_MONEY = 'MOBILE_MONEY',
}

@Entity('payments')
export class Payment {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  @Index()
  reference: string;

  @Column('decimal', { precision: 10, scale: 2 })
  amount: number;

  @Column({
    type: 'enum',
    enum: Currency,
  })
  currency: Currency;

  @Column({
    type: 'enum',
    enum: PaymentMethod,
  })
  payment_method: PaymentMethod;

  @Column()
  customer_phone: string;

  @Column()
  customer_email: string;

  @Column({
    type: 'enum',
    enum: PaymentStatus,
    default: PaymentStatus.INITIATED,
  })
  @Index()
  status: PaymentStatus;

  @Column({ nullable: true })
  provider_transaction_id: string;

  @CreateDateColumn()
  created_at: Date;

  @UpdateDateColumn()
  updated_at: Date;
}