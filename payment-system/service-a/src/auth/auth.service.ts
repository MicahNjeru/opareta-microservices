import {
  Injectable,
  ConflictException,
  UnauthorizedException,
  BadRequestException,
  Inject,
} from '@nestjs/common';
import type { LoggerService } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { WINSTON_MODULE_NEST_PROVIDER } from 'nest-winston';
import { User } from './entities/user.entity';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';
import { ValidateTokenDto } from './dto/validate-token.dto';
import {
  LoginResponseDto,
  UserResponseDto,
  ValidateTokenResponseDto,
} from './dto/auth-response.dto';

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(User)
    private readonly userRepository: Repository<User>,
    private readonly jwtService: JwtService,
    @Inject(WINSTON_MODULE_NEST_PROVIDER)
    private readonly logger: LoggerService,
  ) {}

  async register(registerDto: RegisterDto): Promise<UserResponseDto> {
    const { phone_number, email, password } = registerDto;

    this.logger.log(`Registration attempt for phone: ${phone_number}`);

    // Check if user already exists
    const existingUser = await this.userRepository.findOne({
      where: [{ phone_number }, { email }],
    });

    if (existingUser) {
      if (existingUser.phone_number === phone_number) {
        this.logger.warn(`Phone number already exists: ${phone_number}`);
        throw new ConflictException('Phone number already registered');
      }
      if (existingUser.email === email) {
        this.logger.warn(`Email already exists: ${email}`);
        throw new ConflictException('Email already registered');
      }
    }

    // Hash password
    const saltRounds = 10;
    const password_hash = await bcrypt.hash(password, saltRounds);

    // Create user
    const user = this.userRepository.create({
      phone_number,
      email,
      password_hash,
    });

    const savedUser = await this.userRepository.save(user);

    this.logger.log(`User registered successfully: ${savedUser.id}`);

    return this.toUserResponse(savedUser);
  }

  async login(loginDto: LoginDto): Promise<LoginResponseDto> {
    const { phone_number, password } = loginDto;

    this.logger.log(`Login attempt for phone: ${phone_number}`);

    // Find user by phone number
    const user = await this.userRepository.findOne({ where: { phone_number } });

    if (!user) {
      this.logger.warn(`Login failed - user not found: ${phone_number}`);
      throw new UnauthorizedException('Invalid credentials');
    }

    // Verify password
    const isPasswordValid = await bcrypt.compare(password, user.password_hash);

    if (!isPasswordValid) {
      this.logger.warn(`Login failed - invalid password: ${phone_number}`);
      throw new UnauthorizedException('Invalid credentials');
    }

    // Generate JWT token
    const payload = {
      sub: user.id,
      phone_number: user.phone_number,
      email: user.email,
    };

    const access_token = await this.jwtService.signAsync(payload);

    this.logger.log(`User logged in successfully: ${user.id}`);

    return {
      access_token,
      user: this.toUserResponse(user),
    };
  }

  async validateToken(
    validateTokenDto: ValidateTokenDto,
  ): Promise<ValidateTokenResponseDto> {
    const { token } = validateTokenDto;

    try {
      const payload = await this.jwtService.verifyAsync(token);

      // Find user by ID from token
      const user = await this.userRepository.findOne({
        where: { id: payload.sub },
      });

      if (!user) {
        this.logger.warn(`Token validation failed - user not found: ${payload.sub}`);
        return {
          valid: false,
          message: 'User not found',
        };
      }

      this.logger.log(`Token validated successfully for user: ${user.id}`);

      return {
        valid: true,
        user: this.toUserResponse(user),
      };
    } catch (error) {
      this.logger.warn(`Token validation failed: ${error.message}`);
      return {
        valid: false,
        message: error.message || 'Invalid token',
      };
    }
  }

  private toUserResponse(user: User): UserResponseDto {
    return {
      id: user.id,
      phone_number: user.phone_number,
      email: user.email,
      created_at: user.created_at,
    };
  }
}